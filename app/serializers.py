from __future__ import annotations

from typing import Any

from .models import ActionItem, Contact, FileRecord, Segment
from .utils import (
    KIND_LABEL,
    contact_color,
    contact_initials,
    human_duration_cn,
    human_size,
    iso_utc,
    truncate,
)

STAGE_LABELS = {
    "waiting": "排队中",
    "reading": "读取音频",
    "classifying": "正在分类",
    "transcribing": "正在转写",
    "organizing": "整理摘要",
    "done": "已完成",
    "error": "处理失败",
}

STATUS_LABELS = {
    "queued": "排队中",
    "processing": "处理中",
    "ready": "已归档",
    "failed": "处理失败",
}


def contact_dict(contact: Contact | None) -> dict[str, Any] | None:
    if not contact:
        return None
    return {
        "id": contact.id,
        "name": contact.name,
        "phone": contact.phone,
        "initials": contact_initials(contact.name),
        "color": contact.color or contact_color(contact.name),
    }


def segment_dict(segment: Segment, speakers: dict[str, Any]) -> dict[str, Any]:
    key = str(segment.speaker)
    return {
        "id": segment.id,
        "idx": segment.idx,
        "start": round(segment.start, 2),
        "end": round(segment.end, 2),
        "speaker": key,
        "speaker_name": speakers.get(key, f"说话人 {key}"),
        "text": segment.text,
    }


def action_dict(
    action: ActionItem,
    tz: str,
    with_file: bool = False,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": action.id,
        "text": action.text,
        "detail": action.detail,
        "due_date": action.due_date.isoformat() if action.due_date else None,
        "due_label": action.due_label,
        "priority": action.priority,
        "done": action.done,
        "segment_idx": action.segment_idx,
        "segment_start": action.segment_start,
        "source": action.source,
        "created_at": iso_utc(action.created_at),
    }
    if with_file and action.file:
        file = action.file
        contact = contact_dict(file.contact)
        payload["recording"] = {
            "id": file.id,
            "title": file.title or file.name,
            "name": file.name,
            "kind": file.kind,
            "kind_label": KIND_LABEL.get(file.kind, "文件"),
            "recorded_at": iso_utc(file.recorded_at or file.uploaded_at),
            "contact": contact,
        }
    return payload


def file_summary(record: FileRecord, tz: str) -> dict[str, Any]:
    actions = list(record.actions)
    actions_open = sum(1 for action in actions if not action.done)
    contact = contact_dict(record.contact)
    title = record.title or record.name
    return {
        "id": record.id,
        "name": record.name,
        "rel_path": record.rel_path,
        "kind": record.kind,
        "kind_label": KIND_LABEL.get(record.kind, "文件"),
        "category": record.category,
        "status": record.status,
        "status_label": STATUS_LABELS.get(record.status, record.status),
        "stage": record.stage,
        "stage_label": STAGE_LABELS.get(record.stage, record.stage),
        "error": record.error,
        "title": title,
        "summary": record.summary,
        "excerpt": truncate(record.summary or "", 96),
        "duration": record.duration,
        "duration_label": human_duration_cn(record.duration),
        "size": record.size,
        "size_label": human_size(record.size),
        "recorded_at": iso_utc(record.recorded_at or record.uploaded_at),
        "uploaded_at": iso_utc(record.uploaded_at),
        "processed_at": iso_utc(record.processed_at),
        "contact": contact,
        "topics": record.topics or [],
        "tags": record.tags or [],
        "action_open": actions_open,
        "action_total": len(actions),
        "has_audio": record.kind in {"call", "voice", "audio"},
        "audio_url": f"/api/recordings/{record.id}/audio" if record.kind in {"call", "voice", "audio"} else None,
        "is_demo": record.is_demo,
        "play_count": record.play_count,
        "model": record.model,
        "waveform": record.waveform or [],
    }


def file_detail(record: FileRecord, tz: str) -> dict[str, Any]:
    payload = file_summary(record, tz)
    speakers = record.speakers or {"1": "说话人 1", "2": "说话人 2"}
    payload.update(
        {
            "key_points": record.key_points or [],
            "speakers": speakers,
            "speaker_mode": record.speaker_mode,
            "transcript_source": record.transcript_source,
            "analysis_source": record.analysis_source,
            "language": record.language,
            "sha256": record.sha256,
            "waveform": record.waveform or [],
            "segments": [
                segment_dict(segment, speakers)
                for segment in sorted(record.segments, key=lambda item: item.idx)
            ],
            "actions": [action_dict(action, tz) for action in sorted(record.actions, key=lambda item: (item.created_at, item.id))],
        }
    )
    return payload
