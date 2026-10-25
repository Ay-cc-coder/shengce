from __future__ import annotations

from datetime import date

from app.analysis import analyse_local, parse_due
from app.conversation import Turn
from app.utils import guess_contact_and_title


def test_parse_due_relative_weekday() -> None:
    base = date(2026, 10, 26)  # Monday
    due, label = parse_due("周五之前把颜色确认一下", base)
    assert due == date(2026, 10, 30)
    assert label and label.startswith("周五") and "前" in label

    due, label = parse_due("明天下午三点前发我", base)
    assert due == date(2026, 10, 27)
    assert label and "15:00" in label


def test_local_analysis_extracts_actions() -> None:
    turns = [
        Turn(0, 4, "1", "喂，是我。明天下午师傅过去复尺，你在家吗？"),
        Turn(5, 8, "2", "在，我尽量早点回来。"),
        Turn(9, 14, "1", "你把现在台面的颜色拍一张发我，周五之前要定下来。"),
        Turn(15, 18, "2", "好，我晚上拍给你，周五前给你准信。"),
    ]
    analysis = analyse_local(
        turns,
        contact_name="陈岚",
        kind="call",
        base_date=date(2026, 10, 26),
        fallback_title="橱柜复尺",
    )
    assert analysis.summary
    assert "装修" in analysis.topics or "家居" in analysis.topics
    assert len(analysis.actions) >= 2
    assert any("台面" in item.text for item in analysis.actions)


def test_filename_contact_and_title() -> None:
    contact, phone, title = guess_contact_and_title(
        "通话录音 陈岚 2026-10-24 19-42-18", "Asia/Shanghai"
    )
    assert contact == "陈岚"
    assert title is None or "陈岚" not in title
    contact, _phone, title = guess_contact_and_title("牙科预约 2026-10-24", "Asia/Shanghai")
    assert contact is None
    assert title and "预约" in title


def test_parse_due_with_weekday_and_chinese_hour() -> None:
    base = date(2026, 10, 26)
    due, label = parse_due("好，我约下周二三点半。", base)
    assert due == date(2026, 10, 27)
    assert label == "周二 03:30"


def test_contiguous_whisper_segments_become_turns() -> None:
    from app.conversation import build_conversation
    from app.transcribe import TranscriptSegment

    segments = [
        TranscriptSegment(0.0, 2.5, "你上次补牙的位置还疼吗?"),
        TranscriptSegment(2.5, 5.7, "不疼了，就是咬东西有点酸。"),
        TranscriptSegment(5.7, 9.9, "那下周二下午来复查一下。"),
        TranscriptSegment(9.9, 11.9, "好，我约下周二三点半。"),
    ]
    turns, mode = build_conversation(segments, "call", True)
    assert len(turns) == 4
    assert mode == "alternating"
    assert [turn.speaker for turn in turns] == ["1", "2", "1", "2"]
