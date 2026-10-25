from __future__ import annotations

from fastapi import APIRouter, Query, Request
from sqlalchemy import func, or_, select
from sqlalchemy.orm import selectinload

from ..models import FileRecord
from ..serializers import file_summary

router = APIRouter(prefix="/api/files", tags=["files"])

LIBRARY_KINDS = {"document": "文档", "image": "图片", "video": "视频", "archive": "压缩包", "other": "其他"}


@router.get("")
def list_files(
    request: Request,
    q: str = Query("", max_length=200),
    category: str = Query("", max_length=40),
    kind: str = Query("", max_length=24),
    page: int = Query(1, ge=1),
    page_size: int = Query(30, ge=1, le=100),
) -> dict:
    db = request.app.state.db
    conditions = []
    if category:
        conditions.append(FileRecord.category == category)
    if kind:
        if kind == "audio":
            conditions.append(FileRecord.kind.in_({"call", "voice", "audio"}))
        elif kind == "document":
            conditions.append(FileRecord.kind.in_({"document", "other"}))
        else:
            conditions.append(FileRecord.kind == kind)
    if q.strip():
        like = f"%{q.strip()}%"
        conditions.append(
            or_(
                FileRecord.name.ilike(like),
                FileRecord.title.ilike(like),
                FileRecord.category.ilike(like),
            )
        )

    with db.session() as session:
        total = session.scalar(
            select(func.count()).select_from(FileRecord).where(*conditions)
        ) or 0
        rows = session.scalars(
            select(FileRecord)
            .where(*conditions)
            .options(selectinload(FileRecord.contact), selectinload(FileRecord.actions))
            .order_by(FileRecord.uploaded_at.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        ).all()
        items = [file_summary(row, request.app.state.settings.tz) for row in rows]

        category_rows = session.execute(
            select(FileRecord.category, func.count()).group_by(FileRecord.category)
        ).all()
        categories = [{"name": name or "其他", "count": count} for name, count in category_rows]
        categories.sort(key=lambda item: (-item["count"], item["name"]))

        kind_rows = session.execute(
            select(FileRecord.kind, func.count()).group_by(FileRecord.kind)
        ).all()
        kinds = {name: count for name, count in kind_rows}

    return {
        "items": items,
        "total": total,
        "page": page,
        "page_size": page_size,
        "pages": max(1, (total + page_size - 1) // page_size),
        "categories": categories,
        "kind_counts": kinds,
    }
