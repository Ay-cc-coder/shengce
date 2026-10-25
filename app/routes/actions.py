from __future__ import annotations

from typing import Optional

from datetime import date
import re

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from ..models import ActionItem, FileRecord, utcnow
from ..serializers import action_dict

router = APIRouter(prefix="/api/actions", tags=["actions"])


def _query(request: Request, status: str, q: str, contact_id: str):
    db = request.app.state.db
    conditions = []
    if status == "open":
        conditions.append(ActionItem.done.is_(False))
    elif status == "done":
        conditions.append(ActionItem.done.is_(True))
    if q.strip():
        like = f"%{q.strip()}%"
        conditions.append(ActionItem.text.ilike(like))
    if contact_id:
        conditions.append(FileRecord.contact_id == contact_id)
    stmt = (
        select(ActionItem)
        .join(FileRecord, ActionItem.file_id == FileRecord.id)
        .where(*conditions)
        .options(selectinload(ActionItem.file).selectinload(FileRecord.contact))
    )
    return db, stmt


@router.get("")
def list_actions(
    request: Request,
    status: str = Query("all", pattern="^(all|open|done)$"),
    q: str = Query("", max_length=200),
    contact_id: str = Query("", max_length=40),
) -> dict:
    db, stmt = _query(request, status, q, contact_id)
    with db.session() as session:
        rows = session.scalars(stmt).all()
        open_rows = [row for row in rows if not row.done]
        done_rows = [row for row in rows if row.done]

        def due_minutes(item: ActionItem) -> int:
            match = re.search(r"(\d{1,2}):(\d{2})", item.due_label or "")
            return int(match.group(1)) * 60 + int(match.group(2)) if match else 24 * 60

        def sort_open(item: ActionItem):
            return (
                item.due_date is None,
                item.due_date or date.max,
                due_minutes(item),
                0 if item.priority == "high" else 1,
                item.created_at,
            )

        open_rows.sort(key=sort_open)
        done_rows.sort(key=lambda item: item.completed_at or item.created_at, reverse=True)
        ordered = open_rows + done_rows if status == "all" else rows
        items = [action_dict(item, request.app.state.settings.tz, with_file=True) for item in ordered]
    return {
        "items": items,
        "open_count": len(open_rows),
        "done_count": len(done_rows),
        "total": len(items),
    }


class ActionUpdate(BaseModel):
    done: Optional[bool] = None
    text: Optional[str] = None


@router.patch("/{action_id}")
def update_action(request: Request, action_id: str, body: ActionUpdate) -> dict:
    db = request.app.state.db
    with db.session() as session:
        action = session.scalar(
            select(ActionItem)
            .where(ActionItem.id == action_id)
            .options(selectinload(ActionItem.file).selectinload(FileRecord.contact))
        )
        if not action:
            raise HTTPException(status_code=404, detail="待办不存在。")
        if body.done is not None:
            action.done = body.done
            action.completed_at = utcnow() if body.done else None
        if body.text is not None and body.text.strip():
            action.text = body.text.strip()[:240]
        session.flush()
        payload = action_dict(action, request.app.state.settings.tz, with_file=True)
    return {"item": payload}
