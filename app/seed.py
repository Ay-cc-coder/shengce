from __future__ import annotations

import json
import shutil
from datetime import date, datetime, time, timedelta
from pathlib import Path

from sqlalchemy import func, select

from .config import Settings
from .db import Database
from .ingest import create_contact
from .models import ActionItem, FileRecord, Segment, utcnow
from .utils import (
    KIND_CATEGORY,
    local_to_utc,
    local_zone,
    sha256_file,
)

DEMO_DIR = Path(__file__).resolve().parent.parent / "demo"
DEMO_MEDIA = DEMO_DIR / "media"
DEMO_DATA = DEMO_DIR / "data"


def _due_date(rule: dict, today: date) -> tuple[date | None, str | None]:
    if not rule:
        return None, None
    hour = rule.get("time")
    if rule.get("type") == "offset":
        days = int(rule.get("days", 0))
        target = today + timedelta(days=days)
        prefix = {0: "今天", 1: "明天", 2: "后天"}.get(days)
        if prefix is None:
            prefix = f"{target.month}月{target.day}日"
    elif rule.get("type") == "weekday":
        weekday = int(rule.get("weekday", 0))
        delta = (weekday - today.weekday()) % 7
        target = today + timedelta(days=delta)
        prefix = "周" + "一二三四五六日"[weekday]
    else:
        return None, None
    label = prefix
    if rule.get("before"):
        label += "前"
    if hour:
        label += f" {hour}"
    return target, label


def _audio_for(manifest: dict) -> Path | None:
    name = manifest.get("audio")
    if not name:
        return None
    candidate = DEMO_MEDIA / name
    return candidate if candidate.exists() else None


def seed_demo_data(db: Database, settings: Settings) -> bool:
    if not DEMO_DATA.exists():
        return False
    with db.session() as session:
        count = session.scalar(select(func.count()).select_from(FileRecord)) or 0
        if count:
            return False

    now_local = datetime.now(local_zone(settings.tz))
    today = now_local.date()
    manifests = sorted(DEMO_DATA.glob("*.json"))
    if not manifests:
        return False

    with db.session() as session:
        for index, manifest_path in enumerate(manifests):
            try:
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            except Exception:
                continue
            audio = _audio_for(manifest)
            if not audio:
                continue
            days_ago = int(manifest.get("days_ago", 0))
            time_text = manifest.get("time", "12:00")
            hour, minute = [int(part) for part in time_text.split(":")[:2]]
            recorded_local = datetime.combine(
                today - timedelta(days=days_ago), time(hour=hour, minute=minute)
            )
            recorded_at = local_to_utc(recorded_local, settings.tz)
            kind = manifest.get("kind", "call")
            contact_name = manifest.get("contact")
            contact = (
                create_contact(session, contact_name, manifest.get("phone"))
                if contact_name
                else None
            )
            date_prefix = recorded_local.strftime("%Y-%m-%d %H-%M")
            safe_contact = contact_name or manifest.get("title", "语音备忘")
            rel_path = f"演示/{KIND_CATEGORY.get(kind, '录音')}/{date_prefix} {safe_contact}.m4a"
            target = settings.library_dir / rel_path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(audio, target)
            try:
                target.chmod(0o640)
            except OSError:
                pass

            speakers = manifest.get("speakers") or (
                {"1": contact_name or "说话人 1", "2": "我"}
                if kind == "call"
                else {"me": "我"}
            )
            segments = manifest.get("segments") or []
            text = " ".join(item.get("text", "") for item in segments)
            uploaded_at = utcnow() - timedelta(minutes=index * 37)
            record = FileRecord(
                rel_path=rel_path,
                name=target.name,
                ext=".m4a",
                mime="audio/mp4",
                size=target.stat().st_size,
                sha256=sha256_file(target),
                kind=kind,
                category=KIND_CATEGORY.get(kind, "通话录音"),
                status="ready",
                stage="done",
                title=manifest.get("title") or safe_contact,
                summary=manifest.get("summary"),
                key_points=manifest.get("key_points") or [],
                topics=manifest.get("topics") or [],
                tags=manifest.get("topics") or [],
                speakers=speakers,
                speaker_mode="manual",
                language="zh",
                transcript_text=text,
                transcript_source="demo",
                analysis_source="demo",
                model="demo",
                duration=float(manifest.get("duration") or 0),
                waveform=manifest.get("waveform") or [],
                recorded_at=recorded_at,
                uploaded_at=uploaded_at,
                processed_at=utcnow(),
                fs_mtime=target.stat().st_mtime,
                contact_id=contact.id if contact else None,
                source="demo",
                is_demo=True,
            )
            session.add(record)
            session.flush()
            for seg_index, item in enumerate(segments):
                session.add(
                    Segment(
                        file_id=record.id,
                        idx=seg_index,
                        start=float(item.get("start", 0)),
                        end=float(item.get("end", 0)),
                        speaker=str(item.get("speaker", "1")),
                        text=str(item.get("text", "")),
                    )
                )
            fixture_dir = settings.data_dir / "transcripts"
            fixture_dir.mkdir(exist_ok=True)
            (fixture_dir / f"{target.stem}.json").write_text(
                json.dumps(
                    {
                        "language": "zh",
                        "segments": [
                            {
                                "start": item.get("start", 0),
                                "end": item.get("end", 0),
                                "text": item.get("text", ""),
                            }
                            for item in segments
                        ],
                    },
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
            for action in manifest.get("actions") or []:
                due, label = _due_date(action.get("due_rule") or {}, today)
                line_index = action.get("line_index")
                start = (
                    float(segments[line_index].get("start", 0))
                    if isinstance(line_index, int) and 0 <= line_index < len(segments)
                    else None
                )
                done = bool(action.get("done"))
                session.add(
                    ActionItem(
                        file_id=record.id,
                        text=action.get("text", ""),
                        detail=action.get("detail")
                        or (
                            segments[line_index].get("text")
                            if isinstance(line_index, int) and 0 <= line_index < len(segments)
                            else None
                        ),
                        due_date=due,
                        due_label=label,
                        priority=action.get("priority", "normal"),
                        done=done,
                        segment_idx=line_index if isinstance(line_index, int) else None,
                        segment_start=start,
                        source="demo",
                        completed_at=utcnow() if done else None,
                    )
                )

        details = session.scalars(select(FileRecord).limit(1)).all()
        if not details:
            session.rollback()
            return False
    return True
