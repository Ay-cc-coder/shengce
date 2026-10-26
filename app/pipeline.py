from __future__ import annotations

import logging
import threading
import time
from datetime import date, datetime

from sqlalchemy import delete, select

from .analysis import Analysis, analyse_local
from .config import Settings
from .conversation import build_conversation
from .db import Database
from .ingest import apply_document_metadata
from .llm import analyse_with_llm
from .media import analyse_audio
from .models import ActionItem, Contact, FileRecord, Segment, utcnow
from .transcribe import transcribe_audio
from .utils import (
    KIND_CATEGORY,
    local_zone,
    sha256_file,
    truncate,
    utc_to_local,
)

logger = logging.getLogger(__name__)


class PipelineWorker:
    def __init__(self, db: Database, settings: Settings):
        self.db = db
        self.settings = settings
        self.stop_event = threading.Event()
        self.thread: threading.Thread | None = None
        self.paused = False
        self.pause_lock = threading.Lock()

    def start(self) -> None:
        if self.thread and self.thread.is_alive():
            return
        self.recover_stale()
        self.thread = threading.Thread(target=self._run, name="shengce-worker", daemon=True)
        self.thread.start()
        logger.info("pipeline worker started")

    def stop(self) -> None:
        self.stop_event.set()
        if self.thread:
            self.thread.join(timeout=5)

    def set_paused(self, paused: bool) -> None:
        with self.pause_lock:
            self.paused = bool(paused)

    def is_paused(self) -> bool:
        with self.pause_lock:
            return self.paused

    def recover_stale(self) -> None:
        with self.db.session() as session:
            records = session.scalars(
                select(FileRecord).where(FileRecord.status == "processing")
            ).all()
            for record in records:
                record.status = "queued"
                record.stage = "waiting"
                record.error = None

    def _claim(self) -> str | None:
        if self.is_paused():
            return None
        with self.db.session() as session:
            record = session.scalar(
                select(FileRecord)
                .where(FileRecord.status == "queued")
                .order_by(FileRecord.uploaded_at.asc())
                .limit(1)
            )
            if not record:
                return None
            record.status = "processing"
            record.stage = "reading"
            record.error = None
            return record.id

    def _run(self) -> None:
        while not self.stop_event.is_set():
            try:
                file_id = self._claim()
            except Exception as exc:
                logger.exception("worker claim failed: %s", exc)
                time.sleep(3)
                continue
            if not file_id:
                self.stop_event.wait(1.4)
                continue
            try:
                process_file(self.db, self.settings, file_id)
            except Exception:
                logger.exception("unexpected pipeline failure for %s", file_id)
            self.stop_event.wait(0.35)


def _path_for(db: Database, record: FileRecord):
    return db.path.parent / "library" / record.rel_path


def _fail(db: Database, file_id: str, message: str) -> None:
    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if record:
            record.status = "failed"
            record.stage = "error"
            record.error = truncate(message, 300)
            record.processed_at = utcnow()


def _stage(db: Database, file_id: str, stage: str) -> None:
    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if record:
            record.status = "processing"
            record.stage = stage


def _merge_analysis(llm: Analysis | None, local: Analysis) -> Analysis:
    if not llm:
        return local
    if not llm.actions and local.actions:
        llm.actions = local.actions
        llm.source = "hybrid"
        if not llm.key_points:
            llm.key_points = local.key_points
    if not llm.key_points:
        llm.key_points = local.key_points
    if not llm.topics:
        llm.topics = local.topics
    return llm


def process_file(db: Database, settings: Settings, file_id: str) -> None:
    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if not record:
            return
        path = _path_for(db, record)
        rel_name = record.name
        kind_hint = record.kind
        contact = session.get(Contact, record.contact_id) if record.contact_id else None
        contact_name = contact.name if contact else None
        recorded_at = record.recorded_at or record.uploaded_at
        base_date = (
            utc_to_local(recorded_at, settings.tz) or datetime.now(local_zone(settings.tz))
        ).date()
        title_from_name = record.title

    if not path.exists():
        _fail(db, file_id, "文件已不在资料库中，可能被移动或删除。")
        return

    try:
        digest = sha256_file(path)
    except OSError as exc:
        _fail(db, file_id, f"无法读取文件：{exc.strerror or 'IO 错误'}")
        return

    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if record:
            record.sha256 = digest

    try:
        if kind_hint in {"call", "voice", "audio"}:
            _process_audio(
                db,
                settings,
                file_id,
                path,
                kind_hint,
                contact_name,
                base_date,
                title_from_name,
            )
        else:
            _process_file_asset(db, file_id, path)
    except Exception as exc:
        message = str(exc) if isinstance(exc, RuntimeError) else "处理时遇到错误，请重试。"
        logger.exception("processing failed for %s: %s", rel_name, exc)
        _fail(db, file_id, message)


def _process_file_asset(db: Database, file_id: str, path) -> None:  # type: ignore[no-untyped-def]
    _stage(db, file_id, "classifying")
    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if not record:
            return
        apply_document_metadata(record, path)
        record.category = record.category or KIND_CATEGORY.get(record.kind, "其他")
        record.status = "ready"
        record.stage = "done"
        record.processed_at = utcnow()
        record.summary = None


def _refine_kind(kind_hint: str, name: str, turn_count: int, duration: float | None) -> str:
    lower = name.lower()
    if kind_hint in {"call", "voice"}:
        return kind_hint
    if any(hint in lower for hint in ("通话", "call", "dial")):
        return "call"
    if any(hint in lower for hint in ("语音备忘", "语音", "voice memo", "memo")):
        return "voice"
    if turn_count >= 3 and (duration or 0) >= 45:
        return "call"
    if turn_count >= 1:
        return "voice"
    return "audio"


def _process_audio(
    db: Database,
    settings: Settings,
    file_id: str,
    path,
    kind_hint: str,
    contact_name: str | None,
    base_date: date,
    title_from_name: str | None,
) -> None:  # type: ignore[no-untyped-def]
    _stage(db, file_id, "reading")
    info = analyse_audio(path)
    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if not record:
            return
        record.duration = info.duration
        record.waveform = info.peaks
    _stage(db, file_id, "transcribing")
    transcription = transcribe_audio(path, settings)
    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if not record:
            return
        record.model = transcription.model
        record.transcript_source = transcription.source
        record.language = transcription.language

    preview_turns, _preview_mode = build_conversation(
        transcription.segments, "call", has_contact=bool(contact_name)
    )
    kind = _refine_kind(kind_hint, path.name, len(preview_turns), info.duration)
    turns, speaker_mode = build_conversation(
        transcription.segments, kind, has_contact=bool(contact_name)
    )
    if kind == "call" and not contact_name:
        with db.session() as session:
            record = session.get(FileRecord, file_id)
            if record and record.contact_id:
                contact = session.get(Contact, record.contact_id)
                contact_name = contact.name if contact else None

    _stage(db, file_id, "organizing")
    if not turns:
        local = Analysis(
            title=title_from_name or ("通话录音" if kind == "call" else "语音备忘"),
            summary="音频已归档，但没有识别到可转写的语音内容。",
            key_points=[],
            topics=["无语音内容"],
            actions=[],
            source="local",
        )
    else:
        local = analyse_local(
            turns,
            contact_name=contact_name,
            kind=kind,
            base_date=base_date,
            fallback_title=title_from_name if title_from_name not in {"通话录音", "语音备忘", "音频"} else None,
        )
    analysis = _merge_analysis(
        analyse_with_llm(turns, contact_name, kind, base_date, settings), local
    )

    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if not record:
            return
        session.execute(delete(Segment).where(Segment.file_id == file_id))
        session.execute(delete(ActionItem).where(ActionItem.file_id == file_id))
        for index, turn in enumerate(turns):
            session.add(
                Segment(
                    file_id=file_id,
                    idx=index,
                    start=turn.start,
                    end=turn.end,
                    speaker=turn.speaker,
                    text=turn.text,
                )
            )
        record.kind = kind
        record.category = KIND_CATEGORY.get(kind, "音频")
        record.transcript_text = " ".join(turn.text for turn in turns)
        record.title = truncate(analysis.title or title_from_name or "录音整理", 80)
        record.summary = analysis.summary
        record.key_points = analysis.key_points
        record.topics = analysis.topics
        record.tags = analysis.topics
        record.analysis_source = analysis.source
        record.speaker_mode = speaker_mode
        if speaker_mode == "single" and kind == "voice":
            record.speakers = {"me": "我"}
        elif speaker_mode == "single":
            record.speakers = {"1": "说话人 1"}
        else:
            record.speakers = {"1": "说话人 1", "2": "说话人 2"}
        for action in analysis.actions:
            session.add(
                ActionItem(
                    file_id=file_id,
                    text=action.text,
                    detail=action.detail,
                    due_date=action.due_date,
                    due_label=action.due_label,
                    priority=action.priority,
                    segment_idx=action.segment_idx,
                    segment_start=action.segment_start,
                    source=analysis.source,
                )
            )
        record.status = "ready"
        record.stage = "done"
        record.error = None
        record.processed_at = utcnow()
    logger.info(
        "processed %s: %s, %.0fs, %d turns, %d actions",
        path.name,
        kind,
        info.duration or 0,
        len(turns),
        len(analysis.actions),
    )
