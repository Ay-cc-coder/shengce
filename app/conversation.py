from __future__ import annotations

from dataclasses import dataclass

from .transcribe import TranscriptSegment


def _needs_space(left: str, right: str) -> bool:
    if not left or not right:
        return False
    a, b = left[-1], right[0]
    if "\u4e00" <= a <= "\u9fff" or "\u3000" <= a <= "\u303f":
        return False
    if "\u4e00" <= b <= "\u9fff" or "\u3000" <= b <= "\u303f":
        return False
    return True


def _join_text(parts: list[str]) -> str:
    output = ""
    for part in parts:
        part = part.strip()
        if not part:
            continue
        if output and _needs_space(output, part):
            output += " "
        output += part
    return output


@dataclass
class Turn:
    start: float
    end: float
    speaker: str
    text: str


def _raw_turns(segments: list[TranscriptSegment]) -> list[Turn]:
    turns: list[Turn] = []
    for segment in segments:
        if not segment.text:
            continue
        if not turns:
            turns.append(Turn(segment.start, segment.end, "1", segment.text))
            continue
        previous = turns[-1]
        gap = max(0.0, segment.start - previous.end)
        duration = previous.end - previous.start
        closes_turn = previous.text.rstrip().endswith(("。", "！", "？", "!", "?", "…"))
        should_split = (
            gap >= 0.72
            or duration >= 17
            or len(previous.text) >= 180
            or (closes_turn and gap >= 0.42)
            or (closes_turn and len(previous.text) >= 5 and duration >= 0.9)
        )
        if should_split:
            turns.append(Turn(segment.start, segment.end, "1", segment.text))
        else:
            previous.text = _join_text([previous.text, segment.text])
            previous.end = max(previous.end, segment.end)
    return turns


def build_conversation(
    segments: list[TranscriptSegment], kind: str, has_contact: bool
) -> tuple[list[Turn], str]:
    """Turn Whisper segments into chat turns.

    Faster-whisper does not diarize. For calls we alternate speakers at natural
    turn boundaries, which is useful for reading but explicitly heuristic. The
    UI lets the user rename or swap speakers.
    """
    if not segments:
        return [], "auto"

    raw = _raw_turns(segments)
    if not raw:
        return [], "auto"

    if kind in {"voice", "audio"}:
        # Voice memos are usually one person. Keep readable chunks, not one wall.
        merged: list[Turn] = []
        for turn in raw:
            if not merged:
                merged.append(Turn(turn.start, turn.end, "me", turn.text))
                continue
            previous = merged[-1]
            gap = max(0.0, turn.start - previous.end)
            if gap < 2.2 and len(previous.text) < 220:
                previous.text = _join_text([previous.text, turn.text])
                previous.end = max(previous.end, turn.end)
            else:
                merged.append(Turn(turn.start, turn.end, "me", turn.text))
        return merged, "single"

    if kind == "call" and len(raw) > 1:
        for index, turn in enumerate(raw):
            turn.speaker = "1" if index % 2 == 0 else "2"
        return raw, "alternating"

    for turn in raw:
        turn.speaker = "1"
    return raw, "single"


def talk_ratio(turns: list[Turn]) -> dict[str, float]:
    totals: dict[str, float] = {}
    for turn in turns:
        totals[turn.speaker] = totals.get(turn.speaker, 0.0) + max(0.0, turn.end - turn.start)
    total = sum(totals.values()) or 1.0
    return {speaker: round(value / total, 3) for speaker, value in totals.items()}
