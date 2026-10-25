from __future__ import annotations

from typing import Optional

import mimetypes
from datetime import timedelta

from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select
from sqlalchemy.orm import selectinload

from ..ingest import create_contact, queue_reprocess
from ..models import FileRecord, Segment, utcnow
from ..serializers import file_detail, file_summary

router = APIRouter(prefix="/api/recordings", tags=["recordings"])

AUDIO_KINDS = {"call", "voice", "audio"}


def _db(request: Request):
    return request.app.state.db


def _tz(request: Request) -> str:
    return request.app.state.settings.tz


def _load(request: Request, file_id: str) -> FileRecord:
    db = _db(request)
    with db.session() as session:
        record = session.scalar(
            select(FileRecord)
            .where(FileRecord.id == file_id)
            .options(
                selectinload(FileRecord.contact),
                selectinload(FileRecord.actions),
                selectinload(FileRecord.segments),
            )
        )
        if not record:
            raise HTTPException(status_code=404, detail="录音不存在。")
        session.expunge(record)
    return record


@router.get("")
def list_recordings(
    request: Request,
    q: str = Query("", max_length=200),
    kind: str = Query("", max_length=40),
    status: str = Query("", max_length=20),
    contact_id: str = Query("", max_length=40),
    days: int = Query(0, ge=0, le=3650),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    sort: str = Query("recorded", max_length=20),
) -> dict:
    db = _db(request)
    conditions = []
    if kind:
        if kind == "audio":
            conditions.append(FileRecord.kind.in_(AUDIO_KINDS))
        elif kind == "recording":
            conditions.append(FileRecord.kind.in_({"call", "voice"}))
        else:
            conditions.append(FileRecord.kind == kind)
    if status:
        conditions.append(FileRecord.status == status)
    if contact_id:
        conditions.append(FileRecord.contact_id == contact_id)
    if days:
        cutoff = utcnow() - timedelta(days=days)
        conditions.append(
            func.coalesce(FileRecord.recorded_at, FileRecord.uploaded_at) >= cutoff
        )
    if q.strip():
        like = f"%{q.strip()}%"
        segment_exists = (
            select(Segment.id)
            .where(Segment.file_id == FileRecord.id, Segment.text.ilike(like))
            .exists()
        )
        conditions.append(
            or_(
                FileRecord.name.ilike(like),
                FileRecord.title.ilike(like),
                FileRecord.summary.ilike(like),
                FileRecord.transcript_text.ilike(like),
                segment_exists,
            )
        )

    order = (
        FileRecord.uploaded_at.desc()
        if sort == "uploaded"
        else func.coalesce(FileRecord.recorded_at, FileRecord.uploaded_at).desc()
    )

    with db.session() as session:
        base = select(FileRecord).where(*conditions)
        total = session.scalar(
            select(func.count()).select_from(FileRecord).where(*conditions)
        ) or 0
        rows = session.scalars(
            base.options(selectinload(FileRecord.contact), selectinload(FileRecord.actions))
            .order_by(order)
            .offset((page - 1) * page_size)
            .limit(page_size)
        ).all()
        items = [file_summary(row, _tz(request)) for row in rows]
    return {
        "items": items,
        "total": total,
        "page": page,
        "page_size": page_size,
        "pages": max(1, (total + page_size - 1) // page_size),
    }


@router.get("/{file_id}")
def get_recording(request: Request, file_id: str) -> dict:
    record = _load(request, file_id)
    return file_detail(record, _tz(request))


class ContactUpdate(BaseModel):
    contact_name: Optional[str] = Field(default=None, max_length=120)
    contact_id: Optional[str] = Field(default=None, max_length=40)
    title: Optional[str] = Field(default=None, max_length=240)


@router.patch("/{file_id}")
def update_recording(request: Request, file_id: str, body: ContactUpdate) -> dict:
    db = _db(request)
    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if not record:
            raise HTTPException(status_code=404, detail="录音不存在。")
        if body.contact_id is not None:
            if body.contact_id == "":
                record.contact_id = None
            else:
                from ..models import Contact

                contact = session.get(Contact, body.contact_id)
                if not contact:
                    raise HTTPException(status_code=404, detail="联系人不存在。")
                record.contact_id = contact.id
        elif body.contact_name is not None:
            name = body.contact_name.strip()
            if not name:
                record.contact_id = None
            else:
                contact = create_contact(session, name)
                record.contact_id = contact.id
        if body.title is not None and body.title.strip():
            record.title = body.title.strip()
    return get_recording(request, file_id)


class SpeakerUpdate(BaseModel):
    names: dict[str, str] = Field(default_factory=dict)
    swap: bool = False


@router.patch("/{file_id}/speakers")
def update_speakers(request: Request, file_id: str, body: SpeakerUpdate) -> dict:
    db = _db(request)
    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if not record:
            raise HTTPException(status_code=404, detail="录音不存在。")
        speakers = dict(record.speakers or {})
        if body.swap and "1" in speakers and "2" in speakers:
            speakers["1"], speakers["2"] = speakers["2"], speakers["1"]
        for key, value in body.names.items():
            if key in speakers and value.strip():
                speakers[key] = value.strip()[:20]
        record.speakers = speakers
        record.speaker_mode = "manual"
    return get_recording(request, file_id)


@router.post("/{file_id}/reprocess")
def reprocess(request: Request, file_id: str) -> dict:
    db = _db(request)
    ok = queue_reprocess(db, file_id)
    if not ok:
        raise HTTPException(status_code=404, detail="录音不存在。")
    return {"ok": True, "status": "queued"}


@router.post("/{file_id}/played")
def mark_played(request: Request, file_id: str) -> dict:
    db = _db(request)
    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if not record:
            raise HTTPException(status_code=404, detail="录音不存在。")
        record.play_count = (record.play_count or 0) + 1
        record.last_played_at = utcnow()
        play_count = record.play_count
    return {"ok": True, "play_count": play_count}


@router.get("/{file_id}/audio")
def recording_audio(request: Request, file_id: str) -> FileResponse:
    db = _db(request)
    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if not record:
            raise HTTPException(status_code=404, detail="录音不存在。")
        if record.kind not in AUDIO_KINDS:
            raise HTTPException(status_code=404, detail="这个文件没有音频。")
        path = db.path.parent / "library" / record.rel_path
        name = record.name
        mime = record.mime or mimetypes.guess_type(name)[0] or "application/octet-stream"
    if not path.exists():
        raise HTTPException(status_code=404, detail="音频文件不在资料库中。")
    return FileResponse(
        path,
        media_type=mime,
        filename=name,
        content_disposition_type="inline",
        headers={
            "Cache-Control": "private, max-age=3600",
            "Accept-Ranges": "bytes",
        },
    )


@router.get("/{file_id}/download")
def download(request: Request, file_id: str) -> FileResponse:
    db = _db(request)
    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if not record:
            raise HTTPException(status_code=404, detail="文件不存在。")
        path = db.path.parent / "library" / record.rel_path
        name = record.name
    if not path.exists():
        raise HTTPException(status_code=404, detail="文件不在资料库中。")
    return FileResponse(path, filename=name)
