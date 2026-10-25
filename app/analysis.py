from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import date, timedelta

from .conversation import Turn
from .utils import truncate


@dataclass
class ActionDraft:
    text: str
    detail: str
    due_date: date | None = None
    due_label: str | None = None
    priority: str = "normal"
    segment_idx: int | None = None
    segment_start: float | None = None


@dataclass
class Analysis:
    title: str
    summary: str
    key_points: list[str] = field(default_factory=list)
    topics: list[str] = field(default_factory=list)
    actions: list[ActionDraft] = field(default_factory=list)
    source: str = "local"


TOPIC_KEYWORDS: dict[str, list[str]] = {
    "装修": ["橱柜", "台面", "复尺", "瓷砖", "水电", "安装", "装修", "尺寸", "木工", "油漆"],
    "工作": ["项目", "方案", "需求", "交付", "会议", "客户", "预算", "审批", "汇报", "排期"],
    "合同与财务": ["合同", "报价", "发票", "报销", "账单", "定金", "尾款", "付款", "转账", "费用"],
    "家庭": ["妈妈", "爸爸", "家里", "孩子", "周末", "吃饭", "爸妈", "老婆", "老公"],
    "健康": ["医院", "医生", "挂号", "体检", "报告", "复诊", "复查", "诊所", "牙", "洗牙", "药", "手术"],
    "生活服务": ["维修", "快递", "物业", "搬家", "空调", "上门", "保修", "安装师傅"],
    "出行": ["机票", "酒店", "高铁", "行程", "出发", "接机", "车票", "旅行"],
    "社交": ["聚会", "生日", "婚礼", "请客", "聚餐", "见面", "约饭"],
    "教育": ["学校", "老师", "课程", "作业", "考试", "报名", "培训"],
}

WEEKDAY_CN = "一二三四五六日"
WEEKDAY_RE = re.compile(r"(?:下|这|本)?(?:周|星期|礼拜)([一二三四五六日天])")
DATE_RE = re.compile(r"(?:(20\d{2})年)?(\d{1,2})月(\d{1,2})[日号]")
DAY_RE = re.compile(r"(?<![\d])(\d{1,2})[日号](?![\d])")
TIME_RE = re.compile(
    r"(上午|下午|中午|晚上|早上|傍晚|夜里|凌晨)?\s*(\d{1,2})\s*[点:：时]\s*(\d{1,2})?\s*(分|半)?"
)

ACTION_VERBS = (
    "发|发送|发给|确认|安排|准备|带|处理|回复|回电|联系|预约|订|查|问|转|交|改|定|拿|取|"
    "签|付|买|送|接|告诉|提醒|报价|复尺|上门|安装|开会|见面|体检|取报告|报名|寄|还|补|"
    "拍|量|记|写|整|约|存|上传|下载|更新"
)
ACTION_VERB_RE = re.compile(rf"(?:{ACTION_VERBS})")
REQUEST_RE = re.compile(
    r"(麻烦|请|劳烦|帮我|帮忙|需要你|你(?:记得|把|去|来|跟|和|确认|安排|发|准备|带|处理|回复|联系|预约|订|查|问|转|交|改|定|取|签|付))"
)
REMIND_RE = re.compile(r"(记得|别忘了|不要忘|一定要|务必|尽快|马上|今天内|下班前)")
SELF_COMMIT_RE = re.compile(
    r"我.{0,16}(?:明天|后天|周[一二三四五六日天]|下周|今天|晚点|回头|稍后|下午|上午|晚上|月底|之前).{0,24}"
)
FILLER_RE = re.compile(r"^(那个|嗯|呃|就是|然后|其实|这样子|好的|好|行|对)[，,。\s]*")
APPOINTMENT_RE = re.compile(
    r"(约|定在|安排|确认|改到|推迟到).{0,16}(点|号|日|周|星期|上午|下午|晚上|中午)"
)
CN_DIGITS = {"零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5,
             "六": 6, "七": 7, "八": 8, "九": 9}
CN_NUM_RE = re.compile(r"((?:二十[一二三四五六七八九]?)|(?:十[一二三四五六七八九]?)|[零一二三四五六七八九两])(?=\s*[点时])")


def _cn_number(token: str) -> int:
    if "十" not in token:
        return CN_DIGITS.get(token, 0)
    left, _, right = token.partition("十")
    tens = CN_DIGITS.get(left, 1) if left else 1
    ones = CN_DIGITS.get(right, 0) if right else 0
    return tens * 10 + ones


def _normalize_time_text(text: str) -> str:
    return CN_NUM_RE.sub(lambda match: str(_cn_number(match.group(1))), text)


def detect_topics(text: str, kind: str, limit: int = 3) -> list[str]:
    scores: dict[str, int] = {}
    for topic, keywords in TOPIC_KEYWORDS.items():
        score = sum(text.count(keyword) for keyword in keywords)
        if score:
            scores[topic] = score
    ordered = sorted(scores.items(), key=lambda item: (-item[1], item[0]))
    topics = [topic for topic, _ in ordered[:limit]]
    if not topics:
        topics = ["日常沟通"] if kind == "call" else ["语音记录"]
    return topics


def split_sentences(text: str) -> list[str]:
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return []
    parts = re.split(r"(?<=[。！？!?；;])\s*", text)
    output = []
    for part in parts:
        part = part.strip(" ，,、")
        if len(part) >= 2:
            output.append(part)
    if not output and text:
        output = [text]
    return output


def _sentence_rows(turns: list[Turn]) -> list[tuple[int, Turn, str]]:
    rows: list[tuple[int, Turn, str]] = []
    for index, turn in enumerate(turns):
        for sentence in split_sentences(turn.text):
            rows.append((index, turn, sentence))
    return rows


def _key_points(rows: list[tuple[int, Turn, str]], topics: list[str], limit: int = 3) -> list[str]:
    if not rows:
        return []
    topic_words = [word for topic in topics for word in TOPIC_KEYWORDS.get(topic, [])]
    scored: list[tuple[float, int, str]] = []
    for position, (index, _turn, sentence) in enumerate(rows):
        length = len(sentence)
        if length < 6:
            continue
        score = 0.0
        score += min(length, 60) / 40.0
        score += sum(1.8 for word in topic_words if word in sentence)
        if ACTION_VERB_RE.search(sentence):
            score += 1.6
        if re.search(r"\d|周[一二三四五六日天]|明天|后天|今天|上午|下午|晚上", sentence):
            score += 1.3
        if sentence.endswith(("？", "?")):
            score -= 0.8
        if position < 3:
            score += 0.5
        if re.fullmatch(r"(喂|嗯|好的|行|知道了|没事|再见|拜拜)[。！？!?]?", sentence):
            score -= 5
        scored.append((score, index, sentence))
    scored.sort(key=lambda item: -item[0])

    selected: list[tuple[int, str]] = []
    used_turns: set[int] = set()
    for _score, index, sentence in scored:
        if any(sentence == existing for _i, existing in selected):
            continue
        if index in used_turns and len(selected) < limit:
            continue
        selected.append((index, sentence))
        used_turns.add(index)
        if len(selected) >= limit:
            break
    if not selected:
        selected = [(index, sentence) for index, _turn, sentence in rows[:limit]]
    selected.sort(key=lambda item: item[0])
    return [truncate(sentence, 110) for _index, sentence in selected]


def parse_due(sentence: str, base_date: date) -> tuple[date | None, str | None]:
    target: date | None = None
    prefix = ""

    match = DATE_RE.search(sentence)
    if match:
        year = int(match.group(1) or base_date.year)
        month = int(match.group(2))
        day = int(match.group(3))
        try:
            candidate = date(year, month, day)
            if not match.group(1) and candidate < base_date - timedelta(days=1):
                candidate = date(year + 1, month, day)
            target = candidate
        except ValueError:
            target = None
    if target is None:
        day_match = DAY_RE.search(sentence)
        if day_match:
            day = int(day_match.group(1))
            try:
                candidate = date(base_date.year, base_date.month, day)
                if candidate < base_date:
                    if base_date.month == 12:
                        candidate = date(base_date.year + 1, 1, day)
                    else:
                        candidate = date(base_date.year, base_date.month + 1, day)
                target = candidate
            except ValueError:
                target = None

    if target is None:
        relative = None
        if "大后天" in sentence:
            relative = 3
        elif "后天" in sentence:
            relative = 2
        elif "明天" in sentence or "明早" in sentence or "明晚" in sentence:
            relative = 1
        elif "今天" in sentence or "今晚" in sentence or "今天内" in sentence:
            relative = 0
        if relative is not None:
            target = base_date + timedelta(days=relative)
            prefix = {0: "今天", 1: "明天", 2: "后天", 3: "大后天"}[relative]

    weekday_match = WEEKDAY_RE.search(sentence)
    if target is None and weekday_match:
        char = weekday_match.group(1).replace("天", "日")
        target_weekday = WEEKDAY_CN.index(char)
        delta = (target_weekday - base_date.weekday()) % 7
        if delta == 0 and "下周" in sentence:
            delta = 7
        target = base_date + timedelta(days=delta)
        prefix = ("周" if "周" in weekday_match.group(0) else "星期") + char

    if target is None and "月底" in sentence:
        if base_date.month == 12:
            target = date(base_date.year + 1, 1, 1) - timedelta(days=1)
        else:
            target = date(base_date.year, base_date.month + 1, 1) - timedelta(days=1)
        prefix = "月底"

    hour: int | None = None
    minute = 0
    time_match = TIME_RE.search(_normalize_time_text(sentence))
    if time_match:
        marker = time_match.group(1) or ""
        hour = int(time_match.group(2))
        minute = int(time_match.group(3) or 0)
        if time_match.group(4) == "半":
            minute = 30
        if marker in {"下午", "晚上", "傍晚", "夜里"} and hour < 12:
            hour += 12
        if marker == "中午" and hour < 11:
            hour += 12
        if not (0 <= hour <= 23 and 0 <= minute <= 59):
            hour = None
    elif "下班前" in sentence:
        hour, minute = 18, 0
    elif "中午前" in sentence:
        hour, minute = 12, 0

    if target is None and hour is None:
        return None, None
    if target is None:
        target = base_date

    if not prefix:
        if target == base_date:
            prefix = "今天"
        elif target == base_date + timedelta(days=1):
            prefix = "明天"
        elif target == base_date + timedelta(days=2):
            prefix = "后天"
        elif 0 <= (target - base_date).days < 7:
            prefix = "周" + WEEKDAY_CN[target.weekday()]
        else:
            prefix = f"{target.month}月{target.day}日"

    label = prefix
    if "之前" in sentence or "以前" in sentence:
        label += "前"
    if hour is not None:
        label += f" {hour:02d}:{minute:02d}"
    return target, label


def _priority_for(sentence: str, due: date | None, base_date: date) -> str:
    if re.search(r"(马上|尽快|立即|立刻|紧急|今天|今晚|今天内|下班前|中午前)", sentence):
        return "high"
    if due is not None and (due - base_date).days <= 2:
        return "high"
    if due is not None and (due - base_date).days <= 7:
        return "medium"
    return "normal"


def _looks_actionable(sentence: str) -> bool:
    if len(sentence) < 5:
        return False
    if re.fullmatch(r"(喂|嗯|好的|行|知道了|没事|再见|拜拜|对|是|可以)[。！？!?]?", sentence):
        return False
    if not ACTION_VERB_RE.search(sentence):
        return False
    if sentence.endswith(("吗？", "吗?", "呢？", "呢?")) and not REQUEST_RE.search(sentence):
        return False
    if REQUEST_RE.search(sentence) or REMIND_RE.search(sentence):
        return True
    if APPOINTMENT_RE.search(sentence):
        return True
    if SELF_COMMIT_RE.search(sentence):
        return True
    if "把" in sentence and re.search(r"(之前|以前|回头|稍后|明天|后天|周[一二三四五六日天])", sentence):
        return True
    return False


def _action_text(sentence: str) -> str:
    text = FILLER_RE.sub("", sentence).strip(" ，,。；;")
    text = re.sub(r"^(那个|然后|就是|其实)[，,\s]*", "", text)
    return truncate(text, 78)


def extract_actions(
    turns: list[Turn], base_date: date, limit: int = 5
) -> list[ActionDraft]:
    rows = _sentence_rows(turns)
    actions: list[ActionDraft] = []
    seen: set[str] = set()
    for index, turn, sentence in rows:
        if not _looks_actionable(sentence):
            continue
        due, due_label = parse_due(sentence, base_date)
        text = _action_text(sentence)
        key = re.sub(r"[\s，,。；;！？!?]", "", text)
        if not key or key in seen:
            continue
        seen.add(key)
        actions.append(
            ActionDraft(
                text=text,
                detail=truncate(sentence, 180),
                due_date=due,
                due_label=due_label,
                priority=_priority_for(sentence, due, base_date),
                segment_idx=index,
                segment_start=turn.start,
            )
        )
        if len(actions) >= limit:
            break
    return actions


def analyse_local(
    turns: list[Turn],
    contact_name: str | None,
    kind: str,
    base_date: date,
    fallback_title: str | None = None,
) -> Analysis:
    text = " ".join(turn.text for turn in turns)
    topics = detect_topics(text, kind)
    rows = _sentence_rows(turns)
    points = _key_points(rows, topics)
    actions = extract_actions(turns, base_date)

    who = contact_name or "对方"
    topic_text = "、".join(topics)
    lead = next((point for point in points if not point.endswith(("？", "?"))), points[0] if points else "")
    if kind == "call":
        if len(text) < 24:
            summary = f"和{who}的这通电话很短，只确认了{topic_text}。"
        elif contact_name:
            summary = f"和{contact_name}的这通电话主要围绕{topic_text}。"
        else:
            summary = f"这通电话主要围绕{topic_text}。"
        if lead:
            summary += lead
    elif kind == "voice":
        summary = f"这段语音备忘记录了{topic_text}。"
        if lead:
            summary += lead
    else:
        summary = f"这段音频的内容与{topic_text}有关。"
        if lead:
            summary += lead

    if fallback_title:
        title = fallback_title
    elif kind == "call":
        title = f"与{who}的通话"
    else:
        title = truncate(points[0] if points else topic_text, 26)

    return Analysis(
        title=title,
        summary=summary.strip(),
        key_points=points,
        topics=topics,
        actions=actions,
        source="local",
    )
