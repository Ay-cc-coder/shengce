from __future__ import annotations

import json
import logging
import re
from datetime import date
from typing import Any

import httpx

from .analysis import ActionDraft, Analysis
from .config import Settings
from .conversation import Turn
from .utils import truncate

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """你是一个私人录音整理助手。你会收到一段通话或语音备忘的转写，按时间顺序标注了说话人。
你的任务是帮助机主快速理解内容，并找出真正需要机主处理的事项。

硬性要求：
1. 只根据转写内容整理，不补充、不猜测未出现的事实。
2. 说话人 1 和说话人 2 不一定是机主；只有明确指向“你/您”的请求、机主自己的承诺、或明确的预约，才算待办。无法判断时宁可不列。
3. 摘要 2-3 句，用中文，口语自然，不要“本段录音”“综上所述”等套话。
4. 待办写成以动词开头的短句，不超过 30 个汉字；每条必须能在转写中找到原句。
5. due_date 使用 YYYY-MM-DD；无法确定就填 null。priority 只能是 high、normal、low。
6. 输出 JSON，不要 Markdown 代码块。"""

USER_TEMPLATE = """录音信息：
- 类型：{kind}
- 联系人：{contact}
- 录音日期：{recorded_date}

转写：
{transcript}

返回这个 JSON 结构：
{{
  "title": "不超过 18 个汉字的标题",
  "summary": "2-3 句中文摘要",
  "key_points": ["要点 1", "要点 2"],
  "topics": ["主题标签"],
  "actions": [
    {{
      "text": "以动词开头的待办",
      "quote": "转写中的原句",
      "at": 12.3,
      "due_date": "2025-10-31",
      "due_label": "周五前",
      "priority": "high"
    }}
  ]
}}

如果没有需要机主处理的事，actions 返回空数组。"""


def _format_transcript(turns: list[Turn], speaker_names: dict[str, str] | None = None) -> str:
    names = speaker_names or {"1": "说话人 1", "2": "说话人 2", "me": "我"}
    lines = []
    for turn in turns:
        minutes, seconds = divmod(int(turn.start), 60)
        name = names.get(turn.speaker, f"说话人 {turn.speaker}")
        lines.append(f"[{minutes:02d}:{seconds:02d}] {name}: {turn.text}")
    text = "\n".join(lines)
    return text[:24000]


def _parse_json(content: str) -> dict[str, Any] | None:
    content = content.strip()
    if content.startswith("```"):
        content = re.sub(r"^```(?:json)?\s*", "", content)
        content = re.sub(r"\s*```$", "", content)
    start = content.find("{")
    end = content.rfind("}")
    if start == -1 or end == -1 or end <= start:
        return None
    try:
        value = json.loads(content[start : end + 1])
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


def _clean_list(value: Any, limit: int, max_len: int = 120) -> list[str]:
    if not isinstance(value, list):
        return []
    output: list[str] = []
    for item in value:
        if not isinstance(item, str):
            continue
        item = re.sub(r"\s+", " ", item).strip(" -·")
        if item and item not in output:
            output.append(truncate(item, max_len))
        if len(output) >= limit:
            break
    return output


def _match_segment(turns: list[Turn], quote: str, at: Any) -> tuple[int | None, float | None]:
    quote = (quote or "").strip()
    if quote:
        for index, turn in enumerate(turns):
            if quote in turn.text or turn.text in quote:
                return index, turn.start
        for index, turn in enumerate(turns):
            if len(quote) >= 4 and quote[:8] in turn.text:
                return index, turn.start
    try:
        seconds = float(at)
    except (TypeError, ValueError):
        return None, None
    best: tuple[int | None, float | None] = (None, None)
    distance = float("inf")
    for index, turn in enumerate(turns):
        current = abs(turn.start - seconds)
        if current < distance:
            distance = current
            best = (index, turn.start)
    return best if distance <= 8 else (None, None)


def _safe_date(value: Any) -> date | None:
    if not isinstance(value, str):
        return None
    match = re.match(r"^(20\d{2})-(\d{1,2})-(\d{1,2})", value.strip())
    if not match:
        return None
    try:
        return date(int(match.group(1)), int(match.group(2)), int(match.group(3)))
    except ValueError:
        return None


def analyse_with_llm(
    turns: list[Turn],
    contact_name: str | None,
    kind: str,
    base_date: date,
    settings: Settings,
) -> Analysis | None:
    if not settings.llm_enabled or not turns:
        return None
    endpoint = settings.llm_base_url.rstrip("/")
    if not endpoint.endswith("/chat/completions"):
        endpoint += "/chat/completions"
    user_prompt = USER_TEMPLATE.format(
        kind="通话录音" if kind == "call" else "语音备忘",
        contact=contact_name or "未识别",
        recorded_date=base_date.isoformat(),
        transcript=_format_transcript(turns),
    )
    payload: dict[str, Any] = {
        "model": settings.llm_model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": 0.2,
        "response_format": {"type": "json_object"},
    }
    headers = {
        "Authorization": f"Bearer {settings.llm_api_key}",
        "Content-Type": "application/json",
    }

    content: str | None = None
    try:
        with httpx.Client(timeout=settings.llm_timeout) as client:
            response = client.post(endpoint, headers=headers, json=payload)
            if response.status_code in {400, 422}:
                payload.pop("response_format", None)
                response = client.post(endpoint, headers=headers, json=payload)
            response.raise_for_status()
            data = response.json()
            content = data["choices"][0]["message"]["content"]
    except Exception as exc:
        logger.warning("LLM analysis failed: %s", type(exc).__name__)
        return None

    if not isinstance(content, str):
        return None
    data = _parse_json(content)
    if not data:
        logger.warning("LLM returned non-JSON content")
        return None

    summary = data.get("summary")
    if not isinstance(summary, str) or len(summary.strip()) < 8:
        return None
    title = data.get("title")
    title = truncate(title.strip(), 40) if isinstance(title, str) and title.strip() else ""
    key_points = _clean_list(data.get("key_points"), 4, 140)
    topics = _clean_list(data.get("topics"), 4, 20)

    actions: list[ActionDraft] = []
    raw_actions = data.get("actions")
    if isinstance(raw_actions, list):
        for item in raw_actions[:4]:
            if not isinstance(item, dict):
                continue
            text = item.get("text")
            if not isinstance(text, str) or len(text.strip()) < 3:
                continue
            quote = item.get("quote") if isinstance(item.get("quote"), str) else ""
            index, start = _match_segment(turns, quote, item.get("at"))
            priority = item.get("priority")
            if priority not in {"high", "normal", "low"}:
                priority = "normal"
            due_label = item.get("due_label")
            actions.append(
                ActionDraft(
                    text=truncate(text.strip(), 60),
                    detail=truncate(quote or text.strip(), 180),
                    due_date=_safe_date(item.get("due_date")),
                    due_label=truncate(due_label, 40) if isinstance(due_label, str) else None,
                    priority=priority,
                    segment_idx=index,
                    segment_start=start,
                )
            )

    if not title:
        title = f"与{contact_name}的通话" if kind == "call" and contact_name else "录音整理"
    if not topics:
        topics = ["通话"] if kind == "call" else ["语音记录"]

    return Analysis(
        title=title,
        summary=truncate(summary.strip(), 360),
        key_points=key_points,
        topics=topics,
        actions=actions,
        source="llm",
    )
