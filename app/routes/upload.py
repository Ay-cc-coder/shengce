from __future__ import annotations

import re
from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, File, HTTPException, Request, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from starlette.concurrency import run_in_threadpool

from ..ingest import register_existing_file
from ..models import FileRecord
from ..serializers import file_summary
from ..utils import is_temp_name, local_zone

router = APIRouter(prefix="/api/upload", tags=["upload"])


def _safe_name(name: str) -> str:
    name = Path(name or "上传文件").name
    name = re.sub(r"[\x00-\x1f\x7f]", "", name).strip()
    name = name.replace("/", "-").replace("\\", "-")
    if not name or name in {".", ".."} or is_temp_name(name):
        name = "上传文件"
    return name[:180]


@router.post("")
async def upload(request: Request, file: UploadFile = File(...)) -> dict:
    settings = request.app.state.settings
    db = request.app.state.db
    name = _safe_name(file.filename or "上传文件")
    now = datetime.now(local_zone(settings.tz))
    folder = Path("手动上传") / now.strftime("%Y-%m-%d")
    target_dir = settings.library_dir / folder
    await run_in_threadpool(target_dir.mkdir, parents=True, exist_ok=True)

    stem, suffix = Path(name).stem, Path(name).suffix
    target = target_dir / name
    counter = 2
    while target.exists():
        target = target_dir / f"{stem} ({counter}){suffix}"
        counter += 1

    size = 0
    try:
        with target.open("wb") as handle:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                if size > settings.max_upload_bytes:
                    raise HTTPException(
                        status_code=413,
                        detail=f"文件超过 {settings.max_upload_mb} MB 限制。",
                    )
                handle.write(chunk)
    except HTTPException:
        target.unlink(missing_ok=True)
        raise
    except OSError as exc:
        target.unlink(missing_ok=True)
        raise HTTPException(status_code=500, detail="保存文件失败，请检查磁盘空间。") from exc

    rel_path = target.relative_to(settings.library_dir).as_posix()
    file_id, _changed = await run_in_threadpool(
        register_existing_file, db, target, rel_path, "upload"
    )
    if not file_id:
        raise HTTPException(status_code=500, detail="文件已保存，但登记失败。")

    with db.session() as session:
        record = session.scalar(
            select(FileRecord)
            .where(FileRecord.id == file_id)
            .options(selectinload(FileRecord.contact), selectinload(FileRecord.actions))
        )
        payload = file_summary(record, settings.tz) if record else None
    return {"ok": True, "item": payload}
