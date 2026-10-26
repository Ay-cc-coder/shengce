from __future__ import annotations

import logging
import mimetypes
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from .db import Database
from .models import ActionItem, ClassificationRule, Contact, FileRecord, Segment, utcnow
from .utils import (
    KIND_CATEGORY,
    is_probe_file,
    extension,
    guess_contact_and_title,
    is_temp_name,
    kind_for_extension,
    parse_datetime_from_name,
    sha256_file,
    truncate,
)

logger = logging.getLogger(__name__)

CALL_HINTS = ("通话录音", "通话", "call", "dial", "telephone")
VOICE_HINTS = ("语音备忘", "语音", "voice memo", "memo")


def create_contact(session: Session, name: str, phone: str | None = None) -> Contact:
    name = re.sub(r"\s+", " ", name).strip()[:120]
    if not name:
        name = "未识别联系人"
    existing = session.scalar(select(Contact).where(Contact.name == name))
    if existing:
        if phone and not existing.phone:
            existing.phone = phone
        return existing
    contact = Contact(name=name, phone=phone)
    session.add(contact)
    session.flush()
    return contact


PAREN_CONTACT_RE = re.compile(r"[（(]\s*([\u4e00-\u9fff·]{2,4})\s*[）)]")
CONTROL_RE = re.compile(r"[\u200e\u200f\u202a-\u202e\u2066-\u2069]")
GENERIC_CONTACTS = {"来电", "呼出", "呼入", "通话", "通话录音", "未识别联系人", "未知来电"}
STRUCT_ID_RE = re.compile(r"\{[^}]*\}|\[[^\]]*\]")
STRUCT_DATE_RE = re.compile(
    r"(20\d{2})[-_.年]?(\d{1,2})[-_.月]?(\d{1,2})|\d{2,4}[-_.]\d{1,2}[-_.]\d{1,2}"
)


def _contact_from_filename(name: str) -> str | None:
    name = CONTROL_RE.sub("", name)
    for match in PAREN_CONTACT_RE.finditer(name):
        value = match.group(1).strip(" -_.")
        if value in {"未知来电", "未知号码", "陌生人", "未接来电", "通话录音"}:
            continue
        if value:
            return value
    head = re.split(r"[（(]", name)[0]
    cleaned = STRUCT_ID_RE.sub(" ", head)
    cleaned = STRUCT_DATE_RE.sub(" ", cleaned)
    for token in ("CallKit音频", "CallKit", "微信视频", "微信", "语音", "来电", "呼入", "呼出", "拨出", "小1", "小2", "普通通话", "通话录音", "音频", "录音"):
        cleaned = cleaned.replace(token, " ")
    cleaned = re.sub(r"[^\u4e00-\u9fff·]+", " ", cleaned)
    for candidate in re.findall(r"[\u4e00-\u9fff·]{2,6}", cleaned):
        if candidate in GENERIC_CONTACTS or any(token in candidate for token in ("对方", "通话", "语音", "视频")):
            continue
        return candidate
    return None


def _device_from_name(name: str) -> str:
    lower = name.lower()
    if "callkit" in lower:
        return "CallKit"
    if "微信视频" in name:
        return "微信视频"
    if "微信" in name:
        return "微信"
    if "小1" in name:
        return "小1"
    if "小2" in name:
        return "小2"
    if "facetime" in lower:
        return "FaceTime"
    if "普通通话" in name:
        return "电话"
    return "电话"


def _direction_from_name(name: str, kind: str) -> str:
    lower = name.lower()
    if any(token in name for token in ("呼出", "拨出")) or any(
        token in lower for token in ("outgoing", "dial")
    ):
        return "呼出"
    if any(token in name for token in ("来电", "呼入")) or any(
        token in lower for token in ("incoming", "callkit")
    ):
        return "呼入"
    if kind == "voice":
        return "语音备忘"
    if kind == "audio":
        return "音频"
    return "通话"


def _structured_detail(name: str, device: str, contact: str | None) -> str:
    stem = CONTROL_RE.sub("", Path(name).stem)
    cleaned = STRUCT_ID_RE.sub(" ", stem)
    cleaned = STRUCT_DATE_RE.sub(" ", cleaned)
    cleaned = re.sub(r"wxid[_\s]*[A-Za-z0-9]+", " ", cleaned, flags=re.IGNORECASE)
    for token in (device, "CallKit音频", "CallKit", "微信视频", "微信", "小1", "小2", "呼出", "拨出", "来电", "呼入", "普通通话", "与对方的通话", "通话录音", "音频"):
        cleaned = cleaned.replace(token, " ")
    if contact:
        cleaned = cleaned.replace(contact, " ")
    cleaned = re.sub(r"[（()）【】\[\]{}_\-.,，。:：|]+", " ", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" -_.")
    if not cleaned or not re.search(r"[\u4e00-\u9fffA-Za-z]", cleaned):
        return "通话录音"
    return cleaned[:60]


def structured_fields(name: str, kind: str, recorded_at, contact_name: str | None) -> dict[str, str | None]:
    if kind not in {"call", "voice", "audio"}:
        return {}
    name = CONTROL_RE.sub("", name)
    if contact_name in GENERIC_CONTACTS:
        contact_name = None
    direction = _direction_from_name(name, kind)
    device = _device_from_name(name)
    contact = contact_name or _contact_from_filename(name)
    date_part = recorded_at.strftime("%Y-%m-%d") if recorded_at else "未知日期"
    detail = _structured_detail(name, device, contact)
    title = f"{direction}-{device}-{contact or '未识别'}-{date_part}-{detail}"
    category = direction if direction in {"呼入", "呼出"} else ("语音备忘" if kind == "voice" else ("音频" if kind == "audio" else "通话"))
    return {
        "direction": direction,
        "device": device,
        "contact": contact,
        "category": category,
        "title": title[:200],
    }


def _local_recorded_date(recorded_at) -> object:
    if recorded_at is None:
        return None
    if isinstance(recorded_at, datetime):
        value = recorded_at
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.astimezone(ZoneInfo(os.getenv("TZ", "Asia/Shanghai"))).date()
    return recorded_at


def apply_structured_naming(session: Session, record: FileRecord) -> bool:
    contact_name = None
    if record.contact_id:
        contact = session.get(Contact, record.contact_id)
        contact_name = contact.name if contact else None
    if contact_name in GENERIC_CONTACTS:
        contact_name = None
        record.contact_id = None
    fields = structured_fields(
        record.name,
        record.kind,
        _local_recorded_date(record.recorded_at),
        contact_name,
    )
    if not fields:
        return False
    before = (record.title, record.category, record.contact_id)
    if fields["direction"] in {"呼入", "呼出"} and record.kind in {"audio", "voice"}:
        record.kind = "call"
    if fields["contact"] and not record.contact_id:
        contact = create_contact(session, str(fields["contact"]))
        record.contact_id = contact.id
    record.category = str(fields["category"] or record.category)
    record.title = str(fields["title"] or record.title)
    return (record.title, record.category, record.contact_id) != before


def category_for_text(text: str) -> tuple[str, list[str]]:
    rules: list[tuple[str, tuple[str, ...]]] = [
        ("合同与报价", ("合同", "报价", "甲方", "乙方", "条款", "协议", "订单")),
        ("账单与票据", ("发票", "账单", "报销", "付款", "金额", "税额", "收据")),
        ("证件与证明", ("身份证", "护照", "户口", "证明", "证件", "签证")),
        ("医疗与健康", ("医院", "体检", "报告", "处方", "病历", "医生", "挂号")),
        ("工作与项目", ("项目", "会议", "需求", "方案", "排期", "交付", "汇报")),
        ("家居与装修", ("装修", "橱柜", "尺寸", "台面", "安装", "物业", "维修")),
        ("出行与差旅", ("机票", "酒店", "行程", "高铁", "登机", "预订")),
        ("学习与培训", ("课程", "作业", "考试", "培训", "学校", "报名")),
    ]
    hits: list[str] = []
    for category, keywords in rules:
        if any(keyword in text for keyword in keywords):
            hits.append(category)
    return (hits[0] if hits else "其他资料"), hits[:3]


def extract_document_text(path: Path, ext: str) -> str:
    try:
        if ext in {".txt", ".md", ".csv", ".json", ".xml", ".html", ".rtf"}:
            raw = path.read_bytes()[:200_000]
            for encoding in ("utf-8", "gb18030", "utf-16"):
                try:
                    return raw.decode(encoding)
                except UnicodeDecodeError:
                    continue
            return ""
        if ext == ".pdf":
            from pypdf import PdfReader

            reader = PdfReader(str(path))
            chunks: list[str] = []
            for page in reader.pages[:6]:
                chunks.append(page.extract_text() or "")
                if sum(len(chunk) for chunk in chunks) > 12_000:
                    break
            return "\n".join(chunks)
        if ext == ".docx":
            from docx import Document

            document = Document(str(path))
            chunks = [paragraph.text for paragraph in document.paragraphs if paragraph.text.strip()]
            return "\n".join(chunks[:200])
    except Exception as exc:
        logger.info("document extraction skipped for %s: %s", path.name, type(exc).__name__)
    return ""


def initial_kind(name: str, ext: str) -> str:
    base = kind_for_extension(ext)
    if base != "audio":
        return base
    lower = name.lower()
    if any(hint in lower for hint in CALL_HINTS):
        return "call"
    if any(hint in lower for hint in VOICE_HINTS):
        return "voice"
    return "audio"


def _classification_rule(session: Session, name: str) -> ClassificationRule | None:
    lower = name.lower()
    rows = session.scalars(
        select(ClassificationRule)
        .where(ClassificationRule.enabled.is_(True))
        .order_by(ClassificationRule.priority.desc(), ClassificationRule.created_at.asc())
    ).all()
    for rule in rows:
        if rule.match and rule.match.lower() in lower:
            return rule
    return None


def _apply_classification_rule(
    session: Session, record: FileRecord, rule: ClassificationRule
) -> None:
    if rule.kind and rule.kind in KIND_CATEGORY:
        record.kind = rule.kind
        record.category = KIND_CATEGORY.get(rule.kind, record.category)
    if rule.category:
        record.category = rule.category
    if rule.contact:
        contact = create_contact(session, rule.contact)
        record.contact_id = contact.id
    if rule.title:
        contact_name = None
        if record.contact_id:
            contact_obj = session.get(Contact, record.contact_id)
            contact_name = contact_obj.name if contact_obj else None
        title = rule.title.replace("{contact}", contact_name or "").strip(" -·")
        if title:
            record.title = title[:80]


def apply_rules_to_existing(db: Database) -> int:
    changed = 0
    with db.session() as session:
        rows = session.scalars(select(FileRecord)).all()
        for record in rows:
            rule = _classification_rule(session, record.name)
            before = (record.kind, record.category, record.title, record.contact_id)
            if rule is not None:
                _apply_classification_rule(session, record, rule)
            apply_structured_naming(session, record)
            after = (record.kind, record.category, record.title, record.contact_id)
            if after != before:
                changed += 1
    return changed


def _reset_analysis(session: Session, record: FileRecord) -> None:
    session.execute(delete(Segment).where(Segment.file_id == record.id))
    session.execute(delete(ActionItem).where(ActionItem.file_id == record.id))
    record.title = None
    record.summary = None
    record.key_points = []
    record.topics = []
    record.tags = []
    record.speakers = {"1": "说话人 1", "2": "说话人 2"}
    record.speaker_mode = "auto"
    record.transcript_text = ""
    record.transcript_source = ""
    record.analysis_source = ""
    record.model = ""
    record.duration = None
    record.waveform = []
    record.processed_at = None
    record.error = None
    record.contact_id = None
    record.status = "queued"
    record.stage = "waiting"


def upsert_file(
    db: Database,
    path: Path,
    rel_path: str,
    source: str = "webdav",
    force: bool = False,
    recorded_at: datetime | None = None,
) -> tuple[str | None, bool]:
    """Register a file and queue it. Returns (file id, changed)."""
    try:
        stat = path.stat()
    except OSError:
        return None, False
    name = path.name
    if is_probe_file(name) or is_temp_name(name):
        return None, False
    ext = extension(path)
    mtime = stat.st_mtime

    with db.session() as session:
        record = session.scalar(select(FileRecord).where(FileRecord.rel_path == rel_path))
        changed = record is None
        if record is not None and not force:
            if record.size == stat.st_size and abs(record.fs_mtime - mtime) < 0.001:
                return record.id, False
        if record is None:
            record = FileRecord(rel_path=rel_path, name=name)
            session.add(record)
            session.flush()
        else:
            changed = True
            _reset_analysis(session, record)

        record.name = name
        record.ext = ext
        record.mime = mimetypes.guess_type(name)[0] or "application/octet-stream"
        record.size = stat.st_size
        record.fs_mtime = mtime
        record.source = source
        record.status = "queued"
        record.stage = "waiting"
        record.error = None
        if not record.uploaded_at or force:
            record.uploaded_at = utcnow()

        kind = initial_kind(name, ext)
        record.kind = kind
        record.category = KIND_CATEGORY.get(kind, "其他")

        stem = path.stem
        tz_name = os.getenv("TZ", "Asia/Shanghai")
        contact_name, phone, guessed_title = guess_contact_and_title(stem, tz_name)
        if kind in {"call", "voice", "audio"} and contact_name:
            contact = create_contact(session, contact_name, phone)
            record.contact_id = contact.id
        parsed_time = recorded_at or parse_datetime_from_name(stem, tz_name)
        if parsed_time is None:
            parsed_time = datetime.fromtimestamp(mtime, tz=timezone.utc).replace(tzinfo=None)
        record.recorded_at = parsed_time

        if kind == "call":
            title = guessed_title or (
                f"与{contact_name}的通话" if contact_name else "通话录音"
            )
        elif kind == "voice":
            title = guessed_title or "语音备忘"
        elif kind == "audio":
            title = guessed_title or truncate(stem, 40)
        else:
            title = guessed_title or truncate(stem, 60)
        record.title = title
        rule = _classification_rule(session, name)
        if rule is not None:
            _apply_classification_rule(session, record, rule)
        apply_structured_naming(session, record)

        session.flush()
        record_id = record.id
    return record_id, changed


def register_existing_file(
    db: Database, path: Path, rel_path: str, source: str = "upload"
) -> tuple[str | None, bool]:
    return upsert_file(db, path, rel_path, source=source, force=True)


def queue_reprocess(db: Database, file_id: str) -> bool:
    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if not record:
            return False
        _reset_analysis(session, record)
        return True


def set_stage(db: Database, file_id: str, stage: str) -> None:
    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if record:
            record.stage = stage
            record.status = "processing"


def remove_record(db: Database, file_id: str, delete_media: bool = True) -> None:
    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if not record:
            return
        if delete_media:
            try:
                (db.path.parent / "library" / record.rel_path).unlink(missing_ok=True)
            except OSError:
                pass
        session.delete(record)


def find_by_rel_path(db: Database, rel_path: str) -> FileRecord | None:
    with db.session() as session:
        return session.scalar(select(FileRecord).where(FileRecord.rel_path == rel_path))


def apply_document_metadata(record: FileRecord, path: Path) -> None:
    if record.kind not in {"document", "other"}:
        return
    text = extract_document_text(path, record.ext)
    if not text.strip():
        record.category = KIND_CATEGORY.get(record.kind, "其他")
        return
    category, tags = category_for_text(text)
    record.category = category
    record.tags = tags
    if not record.title or record.title == path.stem:
        first_line = next((line.strip() for line in text.splitlines() if line.strip()), "")
        if first_line:
            record.title = truncate(first_line, 60)


def scan_library(db: Database) -> int:
    library = db.path.parent / "library"
    changed = 0
    for root, dirs, files in os.walk(library):
        dirs[:] = [item for item in dirs if not item.startswith(".")]
        for filename in files:
            if is_temp_name(filename) or is_probe_file(filename):
                continue
            path = Path(root) / filename
            if path.is_symlink() or not path.is_file():
                continue
            rel_path = path.relative_to(library).as_posix()
            _file_id, did_change = upsert_file(db, path, rel_path, source="scan")
            changed += 1 if did_change else 0
    return changed


def record_sha(db: Database, file_id: str, path: Path) -> str:
    digest = sha256_file(path)
    with db.session() as session:
        record = session.get(FileRecord, file_id)
        if record:
            record.sha256 = digest
    return digest

