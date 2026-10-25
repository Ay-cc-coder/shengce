from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from ..models import Contact, FileRecord
from ..serializers import contact_dict, file_summary
from ..utils import iso_utc

router = APIRouter(prefix="/api/contacts", tags=["contacts"])


def _contact_stats(contact: Contact) -> dict:
    calls = [row for row in contact.files if row.kind == "call" and row.status == "ready"]
    calls.sort(key=lambda row: row.recorded_at or row.uploaded_at, reverse=True)
    return {
        "calls": len(calls),
        "duration": round(sum(row.duration or 0 for row in calls), 1),
        "last_at": iso_utc((calls[0].recorded_at or calls[0].uploaded_at) if calls else None),
        "open_actions": sum(
            1
            for row in calls
            for action in row.actions
            if not action.done
        ),
    }


@router.get("")
def list_contacts(request: Request, q: str = Query("", max_length=120)) -> dict:
    db = request.app.state.db
    with db.session() as session:
        stmt = select(Contact).options(
            selectinload(Contact.files).selectinload(FileRecord.actions)
        )
        if q.strip():
            stmt = stmt.where(Contact.name.ilike(f"%{q.strip()}%"))
        rows = session.scalars(stmt).all()
        items = []
        for contact in rows:
            stats = _contact_stats(contact)
            items.append({"contact": contact_dict(contact), **stats})
        items.sort(key=lambda item: (-item["calls"], item["contact"]["name"]))
    return {"items": items}


@router.get("/{contact_id}")
def contact_detail(request: Request, contact_id: str) -> dict:
    db = request.app.state.db
    with db.session() as session:
        contact = session.scalar(
            select(Contact)
            .where(Contact.id == contact_id)
            .options(
                selectinload(Contact.files).selectinload(FileRecord.actions),
                selectinload(Contact.files).selectinload(FileRecord.contact),
            )
        )
        if not contact:
            raise HTTPException(status_code=404, detail="联系人不存在。")
        stats = _contact_stats(contact)
        files = sorted(
            [row for row in contact.files if row.status == "ready"],
            key=lambda row: row.recorded_at or row.uploaded_at,
            reverse=True,
        )
        payload = {
            "contact": contact_dict(contact),
            **stats,
            "recordings": [file_summary(row, request.app.state.settings.tz) for row in files],
        }
    return payload


class ContactPatch(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    note: Optional[str] = Field(default=None, max_length=1000)


@router.patch("/{contact_id}")
def update_contact(request: Request, contact_id: str, body: ContactPatch) -> dict:
    db = request.app.state.db
    with db.session() as session:
        contact = session.get(Contact, contact_id)
        if not contact:
            raise HTTPException(status_code=404, detail="联系人不存在。")
        name = body.name.strip()
        if not name:
            raise HTTPException(status_code=422, detail="联系人名称不能为空。")
        existing = session.scalar(select(Contact).where(Contact.name == name, Contact.id != contact.id))
        if existing:
            raise HTTPException(status_code=409, detail="已经有同名联系人。")
        contact.name = name
        if body.note is not None:
            contact.note = body.note
        session.flush()
        return {"contact": contact_dict(contact)}
