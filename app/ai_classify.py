from __future__ import annotations

import logging
import time
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

SYSTEM_PROMPT = """你是一个录音文件命名分类助手。用户会给出一批文件名样本（以及去重后的命名模式）。
请归纳稳定的“词表规则”，让程序以后不用每条都调用 AI。规则只需要识别文件名中的前缀、方向和设备；
联系人姓名、日期、详细内容都是每个文件不同的变量，不能固化在规则里。

要求：
1. match 必须是文件名中稳定出现的短子串，1-24 个字符；不要包含日期、UUID、随机数字、联系人姓名或 wxid；末尾不要带 -、_ 或空格。
2. direction 只能是：呼入、呼出、未知。文件名有“来电/呼入”就是呼入，有“呼出/拨出”就是呼出；CallKit 音频通常按呼入。
3. device 是拨打的设备/平台：移动、联通、电信、CallKit、微信、微信视频、小1、小2、FaceTime、电话等；用文件名里真实出现的。
4. kind 只能是 call、voice、audio、document、image、video、archive、other。
5. category 是 2-12 个汉字；通话建议直接用“呼入”或“呼出”，语音备忘用“语音备忘”。
6. title_template 使用占位符，默认必须是：
   {direction}-{device}-{contact}-{date}-{detail}
   不要写死具体人名或日期，不要改写这个模板。
7. 不要为每个联系人单独建规则；联系人由程序从括号等位置提取。
8. 覆盖所有不同的文件名前缀，最多返回 30 条规则。
9. 只返回 JSON，不要 Markdown。格式：
{"rules":[{"match":"CallKit音频","direction":"呼入","device":"CallKit","kind":"call","category":"呼入","title_template":"{direction}-{device}-{contact}-{date}-{detail}"}]}
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
    elif path.rstrip("/").endswith("/v1"):
        candidates.append(base[: -len("/v1")].rstrip("/"))
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
    transient = {502, 503, 504}
    with httpx.Client(timeout=settings.llm_timeout) as client:
        for attempt in range(2):
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
                if response.status_code in {404, 405} | transient:
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
            if attempt == 0:
                time.sleep(1.0)
    raise RuntimeError(f"AI 接口暂不可用：{last_error or '没有可用地址'}。如果反复 502，通常是服务商上游问题，换一个模型或服务商再试。")


def list_models(settings: Settings) -> list[str]:
    last_error: Exception | None = None
    endpoints: list[str] = []
    for base in _api_bases(settings.llm_base_url):
        url = base + "/models"
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
        match = str(item.get("match") or "").strip().rstrip("-_ ")
        if not (1 <= len(match) <= 24) or match in seen:
            continue
        kind = str(item.get("kind") or "").strip().lower()
        if kind not in ALLOWED_KINDS:
            kind = ""
        direction = str(item.get("direction") or "").strip()
        if direction not in {"呼入", "呼出", "未知"}:
            direction = ""
        rule = {
            "match": match,
            "kind": kind or None,
            "category": truncate(str(item.get("category") or "").strip(), 40) or None,
            "direction": direction or None,
            "device": truncate(str(item.get("device") or "").strip(), 40) or None,
            "title_template": truncate(
                str(item.get("title_template") or "{direction}-{device}-{contact}-{date}-{detail}").strip(),
                200,
            ),
            "title": truncate(str(item.get("title") or "").strip(), 200) or None,
            "contact": truncate(str(item.get("contact") or "").strip(), 120) or None,
        }
        rules.append(rule)
        seen.add(match)
        if len(rules) >= 30:
            break
    return rules


def generate_rules(db: Database, settings: Settings) -> dict[str, Any]:
    with db.session() as session:
        names = [
            row
            for row in session.scalars(
                select(FileRecord.name).order_by(FileRecord.uploaded_at.desc()).limit(5000)
            ).all()
        ]
    if not names:
        raise RuntimeError("还没有录音文件，无法生成规则。")
    import re

    unique: list[str] = []
    seen: set[str] = set()
    for name in names:
        pattern = re.sub(r"\{[^}]*\}|\[[^\]]*\]", " ", name)
        pattern = re.sub(
            r"20\d{2}[-_.年]?\d{1,2}[-_.月]?\d{1,2}|\d{2,4}[-_.]\d{1,2}[-_.]\d{1,2}",
            " ",
            pattern,
        )
        pattern = re.sub(r"wxid[_\s]*[A-Za-z0-9]+", " ", pattern, flags=re.IGNORECASE)
        pattern = re.sub(r"\d+", "#", pattern)
        pattern = re.sub(r"\s+", " ", pattern).strip()
        if pattern and pattern not in seen:
            seen.add(pattern)
            unique.append(name)
    sample = "\n".join(unique[:300])
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
            existing.direction = rule["direction"]
            existing.device = rule["device"]
            existing.title_template = rule["title_template"]
            existing.title = rule["title"]
            existing.contact = rule["contact"]
            existing.enabled = True
            existing.source = "ai"
    cleanup_rules(db)
    return {"rules": list_rules(db), "sample_count": len(unique), "generated": len(rules)}


def _normalized_match(value: str) -> str:
    return value.strip().rstrip("-_ ")


def cleanup_rules(db: Database) -> int:
    """Merge rules that differ only by trailing separators."""
    removed = 0
    with db.session() as session:
        rows = session.scalars(
            select(ClassificationRule).order_by(ClassificationRule.created_at.asc())
        ).all()
        groups: dict[str, list[ClassificationRule]] = {}
        for row in rows:
            groups.setdefault(_normalized_match(row.match), []).append(row)
        for normalized, items in groups.items():
            if len(items) == 1 and items[0].match == normalized:
                continue
            items.sort(
                key=lambda row: (
                    bool(row.direction),
                    bool(row.device),
                    bool(row.title_template),
                    bool(row.category),
                ),
                reverse=True,
            )
            keep = items[0]
            for duplicate in items[1:]:
                session.delete(duplicate)
                removed += 1
            keep.match = normalized
    return removed


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
                "direction": row.direction,
                "device": row.device,
                "title_template": row.title_template,
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
    cleanup_rules(db)
    return apply_rules_to_existing(db)


def ai_public(settings: Settings, provider: str = "custom") -> dict[str, Any]:
    return public_ai_config(settings, provider)
