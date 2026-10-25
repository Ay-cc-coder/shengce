from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Request
from sqlalchemy import func, select

from ..models import FileRecord

router = APIRouter(prefix="/api/setup", tags=["setup"])


def _public_base(request: Request, configured: str) -> str:
    if configured:
        return configured.rstrip("/")
    proto = request.headers.get("x-forwarded-proto", "").split(",")[0].strip()
    host = request.headers.get("x-forwarded-host", "").split(",")[0].strip()
    if not host:
        host = request.headers.get("host", "")
    scheme = proto or request.url.scheme
    return f"{scheme}://{host}".rstrip("/")


@router.get("")
def setup_info(request: Request) -> dict:
    settings = request.app.state.settings
    db = request.app.state.db
    base = _public_base(request, settings.public_url)
    with db.session() as session:
        total = session.scalar(select(func.count()).select_from(FileRecord)) or 0
        total_size = session.scalar(select(func.sum(FileRecord.size))) or 0
        queued = session.scalar(
            select(func.count()).select_from(FileRecord).where(FileRecord.status.in_({"queued", "processing"}))
        ) or 0
        failed = session.scalar(
            select(func.count()).select_from(FileRecord).where(FileRecord.status == "failed")
        ) or 0
    return {
        "dav_url": f"{base}/dav/",
        "dav_username": settings.dav_username,
        "dav_password": settings.dav_password if settings.show_dav_password else None,
        "dav_password_visible": settings.show_dav_password,
        "base_url": base,
        "https": base.startswith("https://") or request.headers.get("x-forwarded-proto") == "https",
        "max_upload_mb": settings.max_upload_mb,
        "whisper_model": settings.whisper_model,
        "whisper_language": settings.whisper_language,
        "llm_enabled": settings.llm_enabled,
        "llm_model": settings.llm_model if settings.llm_enabled else None,
        "asr_engine": settings.asr_engine,
        "demo_mode": settings.demo_mode,
        "data_dir": str(settings.data_dir),
        "library_dir": str(settings.library_dir),
        "total_files": total,
        "total_size": total_size,
        "queued": queued,
        "failed": failed,
        "version": request.app.state.version,
    }


@router.get("/storage")
def storage_info(request: Request) -> dict:
    settings = request.app.state.settings
    usage = shutil_usage(settings.data_dir)
    return usage


def shutil_usage(path: Path) -> dict:
    import shutil

    try:
        usage = shutil.disk_usage(path)
        return {
            "total": usage.total,
            "used": usage.used,
            "free": usage.free,
        }
    except OSError:
        return {"total": 0, "used": 0, "free": 0}
