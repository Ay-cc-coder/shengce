from __future__ import annotations

import logging
from typing import Any

import httpx
from sqlalchemy import select

from .ai_config import public_ai_config
from .config import Settings
from .db import Database
from .ingest import apply_rules_to_existing
from .llm import _parse_json
from .models import ClassificationRule, FileRecord
from .utils import truncate

logger = logging.getLogger(__name__)

ALLOWED_KINDS = {"call", "voice", "audio", "document", "image", "video", "archive", "other"}

SYSTEM_PROMPT = """你是一个录音文件命名分类助手。用户会给出一批文件名样本。
请归纳少量稳定的“词表规则”，把文件名中的平台/来源前缀映射成录音分类。规则会用于以后的新文件，避免每个文件都调用 AI。

要求：
1. match 必须是文件名中稳定出现的短子串，1-24 个字符；不要包含日期、UUID、随机数字、联系人姓名。
2. 不要把每个联系人单独做成规则；联系人由程序从文件名里提取。
3. kind 只能是 call、voice、audio、document、image、video、archive、other。
4. category 是 2-12 个汉字，例如“微信来电”“微信呼出”“CallKit 来电”“普通通话”“语音备忘”。
5. title 可选，是不超过 24 字的统一标题；可以用 {contact} 占位，但不要强行编造联系人。
6. 最多返回 20 条规则，按优先级从高到低。
7. 只返回 JSON，不要 Markdown。格式：
{"rules":[{"match":"CallKit音频","kind":"call","category":"CallKit 来电","title":"CallKit 来电"}]}
"""


def _api_bases(base_url: str) -> list[str]:
    base = (base_url or "").strip().rstrip("/")
    if not base:
        raise RuntimeError("还没有填写 AI 服务器地址。")
    if base.endswith("/chat/completions"):
        base = base[: -len("/chat/completions")].rstrip("/")
    if base.endswith("/models"):
        base = base[: -len("/models")].rstrip("/")
    candidates = [base]
    parsed = base.split("://", 1)[-1]
    path = "/" + parsed.split("/", 1)[1] if "/" in parsed else ""
    if path in {"", "/"}:
        candidates = [base + "/v1", base]
    output: list[str] = []
    for item in candidates:
        if item not in output:
            output.append(item)
    return output


def _headers(settings: Settings) -> dict[str, str]:
    headers = {"Content-Type": "application/json"}
    if settings.llm_api_key:
        headers["Authorization"] = f"Bearer {settings.llm_api_key}"
    return headers


def chat(settings: Settings, messages: list[dict[str, str]], max_tokens: int = 1200) -> str:
    last_error: Exception | None = None
    with httpx.Client(timeout=settings.llm_timeout) as client:
        for base in _api_bases(settings.llm_base_url):
            try:
                response = client.post(
                    base + "/chat/completions",
                    headers=_headers(settings),
                    json={
                        "model": settings.llm_model,
                        "messages": messages,
                        "temperature": 0.1,
                        "max_tokens": max_tokens,
                    },
                )
            except httpx.HTTPError as exc:
                last_error = exc
                continue
            if response.status_code in {404, 405}:
                last_error = RuntimeError(f"接口返回 {response.status_code}")
                continue
            if response.status_code >= 400:
                detail = response.text[:200]
                raise RuntimeError(f"AI 接口返回 {response.status_code}：{detail}")
            payload = response.json()
            choices = payload.get("choices") or []
            if not choices:
                raise RuntimeError("AI 服务没有返回 choices。")
            message = choices[0].get("message") or {}
            content = message.get("content")
            if not isinstance(content, str) or not content.strip():
                raise RuntimeError("AI 返回了空内容。")
            return content
    raise RuntimeError(f"无法连接 AI 接口：{last_error or '没有可用地址'}")


def list_models(settings: Settings) -> list[str]:
    last_error: Exception | None = None
    endpoints: list[str] = []
    for base in _api_bases(settings.llm_base_url):
        for suffix in ("/models", "/v1/models"):
            url = base + suffix
            if url not in endpoints:
                endpoints.append(url)
    with httpx.Client(timeout=min(settings.llm_timeout, 30)) as client:
        for url in endpoints:
            try:
                response = client.get(url, headers=_headers(settings))
            except httpx.HTTPError as exc:
                last_error = exc
                continue
            if response.status_code in {404, 405}:
                last_error = RuntimeError(f"{url} 返回 {response.status_code}")
                continue
            if response.status_code >= 400:
                last_error = RuntimeError(f"{url} 返回 {response.status_code}")
                continue
            payload = response.json()
            raw = payload.get("data") if isinstance(payload, dict) else None
            if not isinstance(raw, list):
                last_error = RuntimeError("模型列表格式不正确")
                continue
            models: list[str] = []
            for item in raw:
                value = item.get("id") if isinstance(item, dict) else item
                if isinstance(value, str) and value and value not in models:
                    models.append(value)
            models.sort()
            if models:
                return models
    raise RuntimeError(f"无法获取模型列表：{last_error or '接口没有返回 data'}")


def test_connection(settings: Settings) -> str:
    content = chat(
        settings,
        [
            {"role": "system", "content": "只回复 OK。"},
            {"role": "user", "content": "ping"},
        ],
        max_tokens=8,
    )
    return truncate(content.strip(), 80)


def _validated_rules(payload: dict[str, Any]) -> list[dict[str, Any]]:
    raw = payload.get("rules")
    if not isinstance(raw, list):
        return []
    rules: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in raw:
        if not isinstance(item, dict):
            continue
        match = str(item.get("match") or "").strip()
        if not (1 <= len(match) <= 24) or match in seen:
            continue
        kind = str(item.get("kind") or "").strip().lower()
        if kind not in ALLOWED_KINDS:
            kind = ""
        rule = {
            "match": match,
            "kind": kind or None,
            "category": truncate(str(item.get("category") or "").strip(), 40) or None,
            "title": truncate(str(item.get("title") or "").strip(), 120) or None,
            "contact": truncate(str(item.get("contact") or "").strip(), 120) or None,
        }
        rules.append(rule)
        seen.add(match)
        if len(rules) >= 20:
            break
    return rules


def generate_rules(db: Database, settings: Settings) -> dict[str, Any]:
    with db.session() as session:
        names = [
            row
            for row in session.scalars(
                select(FileRecord.name).order_by(FileRecord.uploaded_at.desc()).limit(160)
            ).all()
        ]
    unique: list[str] = []
    seen: set[str] = set()
    for name in names:
        if name not in seen:
            unique.append(name)
            seen.add(name)
    if not unique:
        raise RuntimeError("还没有录音文件，无法生成规则。")
    sample = "\n".join(unique[:120])
    content = chat(
        settings,
        [
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": "文件名样本：\n" + sample + "\n\n请只返回 JSON。",
            },
        ],
    )
    payload = _parse_json(content)
    if not payload:
        raise RuntimeError("AI 返回的不是可解析的 JSON 规则。")
    rules = _validated_rules(payload)
    if not rules:
        raise RuntimeError("AI 没有生成可用规则，请换一个模型重试。")
    with db.session() as session:
        for rule in rules:
            existing = session.scalar(
                select(ClassificationRule).where(ClassificationRule.match == rule["match"])
            )
            if existing is None:
                existing = ClassificationRule(match=rule["match"], source="ai")
                session.add(existing)
            existing.kind = rule["kind"]
            existing.category = rule["category"]
            existing.title = rule["title"]
            existing.contact = rule["contact"]
            existing.enabled = True
            existing.source = "ai"
    return {"rules": list_rules(db), "sample_count": len(unique), "generated": len(rules)}


def list_rules(db: Database) -> list[dict[str, Any]]:
    with db.session() as session:
        rows = session.scalars(
            select(ClassificationRule).order_by(
                ClassificationRule.priority.desc(), ClassificationRule.created_at.asc()
            )
        ).all()
        return [
            {
                "id": row.id,
                "match": row.match,
                "kind": row.kind,
                "category": row.category,
                "title": row.title,
                "contact": row.contact,
                "enabled": row.enabled,
                "source": row.source,
            }
            for row in rows
        ]


def delete_rule(db: Database, rule_id: str) -> bool:
    with db.session() as session:
        rule = session.get(ClassificationRule, rule_id)
        if not rule:
            return False
        session.delete(rule)
        return True


def apply_rules(db: Database) -> int:
    return apply_rules_to_existing(db)


def ai_public(settings: Settings, provider: str = "custom") -> dict[str, Any]:
    return public_ai_config(settings, provider)
