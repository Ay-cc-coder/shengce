from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from .config import Settings
from .db import Database
from .models import FileRecord
from .serializers import contact_dict, file_summary
from .utils import local_zone, utc_to_local

WEEKDAYS = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]


def _local_date(value: datetime | None, settings: Settings) -> date | None:
    local = utc_to_local(value, settings.tz)
    return local.date() if local else None


def build_stats(db: Database, settings: Settings, days: int = 30) -> dict[str, Any]:
    days = max(1, min(days, 365))
    now_local = datetime.now(local_zone(settings.tz))
    end_date = now_local.date()
    start_date = end_date - timedelta(days=days - 1)

    with db.session() as session:
        calls = session.scalars(
            select(FileRecord)
            .where(FileRecord.kind == "call", FileRecord.status == "ready")
            .options(selectinload(FileRecord.contact), selectinload(FileRecord.actions))
        ).all()
        call_rows = [
            row
            for row in calls
            if (local_date := _local_date(row.recorded_at or row.uploaded_at, settings))
            and start_date <= local_date <= end_date
        ]
        call_rows.sort(
            key=lambda row: row.recorded_at or row.uploaded_at, reverse=True
        )

        total_calls = len(call_rows)
        total_duration = sum(row.duration or 0 for row in call_rows)
        contact_ids = {row.contact_id for row in call_rows if row.contact_id}
        open_actions = sum(
            1 for row in call_rows for action in row.actions if not action.done
        )

        by_contact: dict[str, dict[str, Any]] = {}
        for row in call_rows:
            key = row.contact_id or "__unknown__"
            contact = row.contact
            if contact:
                payload = contact_dict(contact) or {}
            else:
                payload = {
                    "id": None,
                    "name": "未识别联系人",
                    "phone": None,
                    "initials": "?",
                    "color": "slate",
                }
            bucket = by_contact.setdefault(
                key,
                {
                    "contact": payload,
                    "calls": 0,
                    "duration": 0.0,
                    "open_actions": 0,
                    "last_at": None,
                    "last_call_id": None,
                    "last_title": None,
                },
            )
            bucket["calls"] += 1
            bucket["duration"] += row.duration or 0
            bucket["open_actions"] += sum(1 for action in row.actions if not action.done)
            row_date = row.recorded_at or row.uploaded_at
            if bucket["last_at"] is None or row_date > bucket["last_at"]:
                bucket["last_at"] = row_date
                bucket["last_call_id"] = row.id
                bucket["last_title"] = row.title or row.name

        top_contacts = sorted(
            by_contact.values(),
            key=lambda item: (-item["calls"], -item["duration"]),
        )[:8]
        for item in top_contacts:
            item["last_at"] = (
                item["last_at"].isoformat() + "Z" if item["last_at"] else None
            )
            item["duration"] = round(item["duration"], 1)

        daily_map: dict[date, dict[str, Any]] = {
            start_date + timedelta(days=index): {"calls": 0, "duration": 0.0}
            for index in range(days)
        }
        hour_map = {hour: 0 for hour in range(24)}
        weekday_map = {index: 0 for index in range(7)}
        for row in call_rows:
            local = utc_to_local(row.recorded_at or row.uploaded_at, settings.tz)
            if not local:
                continue
            bucket = daily_map.get(local.date())
            if bucket is not None:
                bucket["calls"] += 1
                bucket["duration"] += row.duration or 0
            hour_map[local.hour] += 1
            weekday_map[local.weekday()] += 1

        daily = [
            {
                "date": day.isoformat(),
                "label": f"{day.month}/{day.day}",
                "weekday": WEEKDAYS[day.weekday()],
                "calls": value["calls"],
                "duration": round(value["duration"], 1),
            }
            for day, value in sorted(daily_map.items())
        ]
        peak_hour = max(hour_map, key=lambda hour: hour_map[hour]) if total_calls else None
        peak_weekday_index = (
            max(weekday_map, key=lambda index: weekday_map[index]) if total_calls else None
        )
        recent = [file_summary(row, settings.tz) for row in call_rows[:6]]

        unique_contacts = len(contact_ids)
        if any(row.contact_id is None for row in call_rows):
            unique_contacts += 1

    return {
        "range_days": days,
        "start_date": start_date.isoformat(),
        "end_date": end_date.isoformat(),
        "total_calls": total_calls,
        "total_duration": round(total_duration, 1),
        "unique_contacts": unique_contacts,
        "avg_duration": round(total_duration / total_calls, 1) if total_calls else 0,
        "open_actions": open_actions,
        "top_contacts": top_contacts,
        "daily": daily,
        "hours": [{"hour": hour, "calls": hour_map[hour]} for hour in range(24)],
        "peak_hour": peak_hour,
        "peak_weekday": WEEKDAYS[peak_weekday_index] if peak_weekday_index is not None else None,
        "recent": recent,
    }
