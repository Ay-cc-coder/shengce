from __future__ import annotations

import uuid
from datetime import date, datetime, timezone
from typing import Any, Optional

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    JSON,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def new_id() -> str:
    return uuid.uuid4().hex


class Base(DeclarativeBase):
    pass


class Contact(Base):
    __tablename__ = "contacts"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    name: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    phone: Mapped[Optional[str]] = mapped_column(String(40), nullable=True)
    color: Mapped[str] = mapped_column(String(24), default="ochre")
    note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)

    files: Mapped[list["FileRecord"]] = relationship(back_populates="contact")


class ClassificationRule(Base):
    __tablename__ = "classification_rules"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    match: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    kind: Mapped[Optional[str]] = mapped_column(String(24), nullable=True)
    category: Mapped[Optional[str]] = mapped_column(String(40), nullable=True)
    direction: Mapped[Optional[str]] = mapped_column(String(8), nullable=True)
    device: Mapped[Optional[str]] = mapped_column(String(40), nullable=True)
    title_template: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    title: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    contact: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
    priority: Mapped[int] = mapped_column(Integer, default=0)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    source: Mapped[str] = mapped_column(String(16), default="ai")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class FileRecord(Base):
    __tablename__ = "files"
    __table_args__ = (UniqueConstraint("rel_path", name="uq_files_rel_path"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    rel_path: Mapped[str] = mapped_column(String(1024), index=True)
    name: Mapped[str] = mapped_column(String(512))
    ext: Mapped[str] = mapped_column(String(24), default="")
    mime: Mapped[str] = mapped_column(String(160), default="application/octet-stream")
    size: Mapped[int] = mapped_column(Integer, default=0)
    sha256: Mapped[Optional[str]] = mapped_column(String(64), nullable=True, index=True)

    kind: Mapped[str] = mapped_column(String(24), default="other", index=True)
    category: Mapped[str] = mapped_column(String(32), default="其他")
    status: Mapped[str] = mapped_column(String(24), default="queued", index=True)
    stage: Mapped[str] = mapped_column(String(32), default="waiting")
    error: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    title: Mapped[Optional[str]] = mapped_column(String(240), nullable=True)
    summary: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    key_points: Mapped[list[Any]] = mapped_column(JSON, default=list)
    topics: Mapped[list[Any]] = mapped_column(JSON, default=list)
    tags: Mapped[list[Any]] = mapped_column(JSON, default=list)
    speakers: Mapped[dict[str, Any]] = mapped_column(
        JSON, default=lambda: {"1": "说话人 1", "2": "说话人 2"}
    )
    speaker_mode: Mapped[str] = mapped_column(String(24), default="auto")
    language: Mapped[str] = mapped_column(String(16), default="zh")
    transcript_text: Mapped[str] = mapped_column(Text, default="")
    transcript_source: Mapped[str] = mapped_column(String(32), default="")
    analysis_source: Mapped[str] = mapped_column(String(32), default="")
    model: Mapped[str] = mapped_column(String(120), default="")

    duration: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    waveform: Mapped[list[Any]] = mapped_column(JSON, default=list)
    recorded_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True, index=True)
    uploaded_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)
    processed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    fs_mtime: Mapped[float] = mapped_column(Float, default=0)
    play_count: Mapped[int] = mapped_column(Integer, default=0)
    last_played_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

    contact_id: Mapped[Optional[str]] = mapped_column(
        ForeignKey("contacts.id", ondelete="SET NULL"), nullable=True, index=True
    )
    contact: Mapped[Optional[Contact]] = relationship(back_populates="files")

    source: Mapped[str] = mapped_column(String(24), default="webdav")
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False)

    segments: Mapped[list["Segment"]] = relationship(
        back_populates="file", cascade="all, delete-orphan", order_by="Segment.idx"
    )
    actions: Mapped[list["ActionItem"]] = relationship(
        back_populates="file", cascade="all, delete-orphan"
    )


class Segment(Base):
    __tablename__ = "segments"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    file_id: Mapped[str] = mapped_column(
        ForeignKey("files.id", ondelete="CASCADE"), index=True
    )
    idx: Mapped[int] = mapped_column(Integer)
    start: Mapped[float] = mapped_column(Float)
    end: Mapped[float] = mapped_column(Float)
    speaker: Mapped[str] = mapped_column(String(16), default="1")
    text: Mapped[str] = mapped_column(Text)

    file: Mapped[FileRecord] = relationship(back_populates="segments")


class ActionItem(Base):
    __tablename__ = "actions"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    file_id: Mapped[str] = mapped_column(
        ForeignKey("files.id", ondelete="CASCADE"), index=True
    )
    text: Mapped[str] = mapped_column(Text)
    detail: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    due_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True, index=True)
    due_label: Mapped[Optional[str]] = mapped_column(String(80), nullable=True)
    priority: Mapped[str] = mapped_column(String(16), default="normal")
    done: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    segment_idx: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    segment_start: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    source: Mapped[str] = mapped_column(String(24), default="local")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

    file: Mapped[FileRecord] = relationship(back_populates="actions")
