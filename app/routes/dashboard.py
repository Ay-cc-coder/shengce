from __future__ import annotations

from datetime import datetime, time, timedelta

from fastapi import APIRouter, Query, Request
from sqlalchemy import func, select
from sqlalchemy.orm import selectinload

from ..models import ActionItem, FileRecord
from ..serializers import action_dict, file_detail, file_summary
from ..stats import build_stats
from ..utils import local_to_utc, local_zone

router = APIRouter(prefix="/api", tags=["dashboard"])


@router.get("/badges")
def badges(request: Request) -> dict:
    db = request.app.state.db
    with db.session() as session:
        open_actions = session.scalar(
            select(func.count()).select_from(ActionItem).where(ActionItem.done.is_(False))
        ) or 0
        processing = session.scalar(
            select(func.count())
            .select_from(FileRecord)
            .where(FileRecord.status.in_({"queued", "processing"}))
        ) or 0
        failed = session.scalar(
            select(func.count()).select_from(FileRecord).where(FileRecord.status == "failed")
        ) or 0
        total = session.scalar(select(func.count()).select_from(FileRecord)) or 0
        latest = session.scalar(select(func.max(FileRecord.uploaded_at)))
    return {
        "open_actions": open_actions,
        "processing": processing,
        "failed": failed,
        "total_files": total,
        "latest_upload_at": latest.isoformat() + "Z" if latest else None,
    }


@router.get("/stats")
def stats(request: Request, days: int = Query(30, ge=1, le=365)) -> dict:
    return build_stats(request.app.state.db, request.app.state.settings, days)


@router.get("/overview")
def overview(request: Request) -> dict:
    db = request.app.state.db
    settings = request.app.state.settings
    with db.session() as session:
        audio_rows = session.scalars(
            select(FileRecord)
            .where(FileRecord.kind.in_({"call", "voice", "audio"}))
            .options(
                selectinload(FileRecord.contact),
                selectinload(FileRecord.actions),
                selectinload(FileRecord.segments),
            )
            .order_by(
                func.coalesce(FileRecord.recorded_at, FileRecord.uploaded_at).desc()
            )
            .limit(8)
        ).all()
        latest = next((row for row in audio_rows if row.status == "ready"), None)
        recent = audio_rows[:5]
        actions = session.scalars(
            select(ActionItem)
            .where(ActionItem.done.is_(False))
            .order_by(
                ActionItem.due_date.is_(None),
                ActionItem.due_date,
                ActionItem.due_label,
                ActionItem.created_at,
            )
            .options(selectinload(ActionItem.file).selectinload(FileRecord.contact))
            .limit(4)
        ).all()
        processing = session.scalar(
            select(func.count())
            .select_from(FileRecord)
            .where(FileRecord.status.in_({"queued", "processing"}))
        ) or 0
        total_files = session.scalar(select(func.count()).select_from(FileRecord)) or 0
        total_recordings = session.scalar(
            select(func.count())
            .select_from(FileRecord)
            .where(FileRecord.kind.in_({"call", "voice", "audio"}))
        ) or 0
        failed = session.scalar(
            select(func.count())
            .select_from(FileRecord)
            .where(FileRecord.status == "failed")
        ) or 0
        open_actions_total = session.scalar(
            select(func.count()).select_from(ActionItem).where(ActionItem.done.is_(False))
        ) or 0

        today_local = datetime.now(local_zone(settings.tz)).date()
        start_local = datetime.combine(today_local, time.min)
        end_local = start_local + timedelta(days=1)
        start_utc = local_to_utc(start_local, settings.tz)
        end_utc = local_to_utc(end_local, settings.tz)
        today_count = session.scalar(
            select(func.count())
            .select_from(FileRecord)
            .where(
                FileRecord.uploaded_at >= start_utc,
                FileRecord.uploaded_at < end_utc,
            )
        ) or 0

        payload = {
            "latest": file_detail(latest, settings.tz) if latest else None,
            "recent": [file_summary(row, settings.tz) for row in recent],
            "actions": [
                action_dict(action, settings.tz, with_file=True) for action in actions
            ],
            "stats": build_stats(db, settings, 30),
            "open_actions_total": open_actions_total,
            "processing": processing,
            "failed": failed,
            "total_files": total_files,
            "total_recordings": total_recordings,
            "today_count": today_count,
        }
    return payload
