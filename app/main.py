from __future__ import annotations

import logging
import os
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy import delete
from starlette.middleware.base import BaseHTTPMiddleware

from . import __version__
from .ai_classify import cleanup_rules
from .ai_config import load_ai_config
from .auth import COOKIE_NAME, LoginLimiter, verify_session
from .config import Settings, load_settings
from .db import init_database
from .dav import router as dav_router
from .ingest import scan_library
from .models import ActionItem
from .pipeline import PipelineWorker
from .routes.actions import router as actions_router
from .routes.ai import router as ai_router
from .routes.auth_routes import router as auth_router
from .routes.contacts import router as contacts_router
from .routes.dashboard import router as dashboard_router
from .routes.files import router as files_router
from .routes.recordings import router as recordings_router
from .routes.setup import router as setup_router
from .routes.system import router as system_router
from .routes.upload import router as upload_router
from .runtime import load_runtime
from .seed import seed_demo_data
from .utils import now_utc

logger = logging.getLogger("shengce")

STATIC_DIR = Path(__file__).parent / "static"
OPEN_API_PREFIXES = ("/api/auth/", "/api/health", "/healthz")


class AuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):  # type: ignore[no-untyped-def]
        path = request.url.path
        if path.startswith("/api/") and not any(
            path == prefix or path.startswith(prefix) for prefix in OPEN_API_PREFIXES
        ):
            settings = request.app.state.settings
            if not verify_session(settings, request.cookies.get(COOKIE_NAME)):
                return JSONResponse(status_code=401, content={"detail": "请先登录。"})
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("Referrer-Policy", "same-origin")
        response.headers.setdefault("X-Frame-Options", "SAMEORIGIN")
        return response


def _scanner_loop(app: FastAPI, stop_event: threading.Event) -> None:
    db = app.state.db
    while not stop_event.wait(300):
        try:
            changed = scan_library(db)
            if changed:
                logger.info("library scan queued %s files", changed)
        except Exception:
            logger.exception("library scan failed")


def _cleanup_stale_uploads(settings: Settings) -> None:
    cutoff = time.time() - 3600
    for root, _dirs, files in os.walk(settings.library_dir):
        for name in files:
            if not name.startswith(".upload-") and not name.startswith(
                "audiowatch-connection-test-"
            ):
                continue
            path = Path(root) / name
            try:
                if path.stat().st_mtime < cutoff:
                    path.unlink(missing_ok=True)
            except OSError:
                pass


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings: Settings = app.state.settings
    db = init_database(settings.db_path)
    app.state.db = db
    app.state.limiter = LoginLimiter()
    cleanup_rules(app.state.db)
    if not settings.demo_mode:
        with db.session() as session:
            session.execute(delete(ActionItem).where(ActionItem.source != "user"))
    runtime = load_runtime(settings)
    app.state.ai_provider = load_ai_config(settings).get("provider", "custom")
    logger.info(
        "ASR runtime: device=%s model=%s compute=%s paused=%s",
        settings.whisper_device,
        settings.whisper_model,
        settings.whisper_compute_type,
        runtime.get("worker_paused", False),
    )

    _cleanup_stale_uploads(settings)
    try:
        changed = scan_library(db)
        if changed:
            logger.info("startup scan queued %s files", changed)
    except Exception:
        logger.exception("startup scan failed")

    if settings.seed_demo or settings.demo_mode:
        try:
            seeded = seed_demo_data(db, settings)
            if seeded:
                logger.info("demo data seeded")
        except Exception:
            logger.exception("demo seed failed")

    worker = PipelineWorker(db, settings)
    worker.set_paused(bool(runtime.get("worker_paused", False)))
    app.state.worker = worker
    if settings.start_worker:
        worker.start()

    stop_event = threading.Event()
    scanner = threading.Thread(target=_scanner_loop, args=(app, stop_event), daemon=True)
    scanner.start()
    app.state.stop_event = stop_event
    try:
        yield
    finally:
        stop_event.set()
        if settings.start_worker:
            worker.stop()


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or load_settings()
    app = FastAPI(
        title="声册",
        version=__version__,
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.version = __version__

    app.add_middleware(GZipMiddleware, minimum_size=1200)
    app.add_middleware(AuthMiddleware)

    app.include_router(auth_router)
    app.include_router(dashboard_router)
    app.include_router(recordings_router)
    app.include_router(actions_router)
    app.include_router(contacts_router)
    app.include_router(files_router)
    app.include_router(setup_router)
    app.include_router(ai_router)
    app.include_router(system_router)
    app.include_router(upload_router)
    app.include_router(dav_router)

    @app.get("/api/health")
    @app.get("/healthz")
    def health(request: Request) -> dict:
        db = request.app.state.db if hasattr(request.app.state, "db") else None
        return {
            "ok": True,
            "version": __version__,
            "time": now_utc().isoformat() + "Z",
            "database": bool(db),
        }

    @app.get("/favicon.svg")
    def favicon() -> FileResponse:
        candidate = STATIC_DIR / "favicon.svg"
        if candidate.is_file():
            return FileResponse(candidate, media_type="image/svg+xml")
        return JSONResponse(status_code=404, content={"detail": "Not found"})

    @app.get("/assets/{asset_path:path}")
    def assets(asset_path: str) -> FileResponse:
        candidate = (STATIC_DIR / "assets" / asset_path).resolve()
        if STATIC_DIR.resolve() not in candidate.parents or not candidate.is_file():
            return JSONResponse(status_code=404, content={"detail": "Not found"})
        return FileResponse(candidate)

    @app.get("/")
    @app.get("/{full_path:path}")
    def spa(full_path: str = "") -> FileResponse:
        if full_path in {"api", "dav"} or full_path.startswith(("api/", "dav/")):
            return JSONResponse(status_code=404, content={"detail": "Not found"})
        index = STATIC_DIR / "index.html"
        if index.is_file():
            return FileResponse(index, headers={"Cache-Control": "no-cache"})
        return JSONResponse(
            status_code=503,
            content={
                "detail": "前端尚未构建。开发时请运行 npm run dev，生产时请先 npm run build。"
            },
        )

    return app

