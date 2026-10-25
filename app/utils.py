from __future__ import annotations

import hashlib
import re
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import unquote
from zoneinfo import ZoneInfo

AUDIO_EXTS = {
    ".m4a",
    ".mp3",
    ".wav",
    ".aac",
    ".caf",
    ".amr",
    ".flac",
    ".ogg",
    ".opus",
    ".aiff",
    ".aif",
    ".wma",
}
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".gif", ".webp", ".tiff", ".bmp"}
VIDEO_EXTS = {".mov", ".mp4", ".m4v", ".avi", ".mkv", ".webm", ".3gp"}
DOC_EXTS = {
    ".pdf",
    ".doc",
    ".docx",
    ".txt",
    ".md",
    ".rtf",
    ".csv",
    ".xls",
    ".xlsx",
    ".ppt",
    ".pptx",
    ".pages",
    ".numbers",
    ".key",
    ".json",
    ".xml",
    ".html",
}
ARCHIVE_EXTS = {".zip", ".rar", ".7z", ".tar", ".gz", ".bz2", ".xz"}

GENERIC_TOKENS = [
    "通话录音",
    "通话记录",
    "通话",
    "录音文件",
    "录音",
    "语音备忘录",
    "语音备忘",
    "语音",
    "手机录音",
    "音频",
    "callrecording",
    "callrecorder",
    "call",
    "recording",
    "recorder",
    "audio",
    "voice",
    "memo",
    "iphone",
    "ios",
    "副本",
    "copy",
]

CHINESE_NAME_RE = re.compile(r"^[\u4e00-\u9fff·]{2,6}$")
LATIN_NAME_RE = re.compile(r"^[A-Za-z][A-Za-z .'-]{1,30}$")
PHONE_RE = re.compile(r"(?:\+?86[-\s]?)?(1[3-9]\d{9})")

CONTACT_COLORS = ["ochre", "moss", "clay", "slate", "sand", "indigo", "plum"]


def now_utc() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def iso_utc(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def local_zone(tz_name: str) -> ZoneInfo:
    try:
        return ZoneInfo(tz_name)
    except Exception:
        return ZoneInfo("Asia/Shanghai")


def utc_to_local(value: datetime | None, tz_name: str) -> datetime | None:
    if value is None:
        return None
    aware = value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value
    return aware.astimezone(local_zone(tz_name))


def local_to_utc(value: datetime, tz_name: str) -> datetime:
    aware = value.replace(tzinfo=local_zone(tz_name)) if value.tzinfo is None else value
    return aware.astimezone(timezone.utc).replace(tzinfo=None)


def human_size(num: int | float | None) -> str:
    if not num:
        return "0 B"
    size = float(num)
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size < 1024 or unit == "TB":
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def human_duration(seconds: float | None) -> str:
    if seconds is None:
        return "--:--"
    total = max(0, int(round(seconds)))
    hours, remainder = divmod(total, 3600)
    minutes, secs = divmod(remainder, 60)
    if hours:
        return f"{hours}:{minutes:02d}:{secs:02d}"
    return f"{minutes}:{secs:02d}"


def human_duration_cn(seconds: float | None) -> str:
    if seconds is None:
        return "未知时长"
    total = max(0, int(round(seconds)))
    minutes, secs = divmod(total, 60)
    if minutes >= 60:
        hours, minutes = divmod(minutes, 60)
        return f"{hours} 小时 {minutes} 分"
    if minutes:
        return f"{minutes} 分 {secs} 秒"
    return f"{secs} 秒"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def extension(path: Path | str) -> str:
    return Path(path).suffix.lower()


def kind_for_extension(ext: str) -> str:
    if ext in AUDIO_EXTS:
        return "audio"
    if ext in IMAGE_EXTS:
        return "image"
    if ext in VIDEO_EXTS:
        return "video"
    if ext in ARCHIVE_EXTS:
        return "archive"
    if ext in DOC_EXTS:
        return "document"
    return "other"


KIND_CATEGORY = {
    "call": "通话录音",
    "voice": "语音备忘",
    "audio": "音频",
    "document": "文档",
    "image": "图片",
    "video": "视频",
    "archive": "压缩包",
    "other": "其他",
}

KIND_LABEL = {
    "call": "通话",
    "voice": "语音备忘",
    "audio": "音频",
    "document": "文档",
    "image": "图片",
    "video": "视频",
    "archive": "压缩包",
    "other": "文件",
}


def contact_color(name: str) -> str:
    digest = hashlib.sha1(name.encode("utf-8")).hexdigest()
    return CONTACT_COLORS[int(digest[:8], 16) % len(CONTACT_COLORS)]


def contact_initials(name: str) -> str:
    name = name.strip()
    if not name:
        return "?"
    if re.match(r"^[\u4e00-\u9fff]", name):
        return name[-2:] if len(name) > 2 else name
    parts = [part for part in re.split(r"\s+", name) if part]
    if len(parts) >= 2:
        return (parts[0][0] + parts[-1][0]).upper()
    return name[:2].upper()


def safe_rel_path(raw: str) -> str:
    """Decode a WebDAV path and return a safe relative POSIX path."""
    decoded = unquote(raw or "")
    decoded = decoded.replace("\\", "/").strip("/")
    if "\x00" in decoded:
        raise ValueError("invalid path")
    parts: list[str] = []
    for part in decoded.split("/"):
        if part in {"", "."}:
            continue
        if part == "..":
            raise ValueError("path traversal")
        if part.startswith(".upload-"):
            raise ValueError("reserved path")
        parts.append(part)
    return "/".join(parts)


def resolve_within(root: Path, rel_path: str) -> Path:
    root = root.resolve()
    target = (root / rel_path).resolve()
    if target != root and root not in target.parents:
        raise ValueError("path escapes root")
    return target


def is_probe_file(name: str) -> bool:
    lower = name.lower()
    return lower.startswith("audiowatch-connection-test-") or lower in {
        ".ds_store",
        "thumbs.db",
    }


def is_temp_name(name: str) -> bool:
    lower = name.lower()
    return (
        lower.startswith("._")
        or lower.startswith(".upload-")
        or lower.startswith(".tmp")
        or lower.endswith((".tmp", ".part", ".crdownload", ".download"))
    )


DATETIME_RES = [
    re.compile(
        r"(?P<y>20\d{2})[-_.年](?P<m>\d{1,2})[-_.月](?P<d>\d{1,2})日?"
        r"(?:[ T_-]*(?P<H>\d{1,2})[:.时-](?P<M>\d{2})(?:[:.分-](?P<S>\d{2}))?)?"
    ),
    re.compile(
        r"(?P<y>20\d{2})(?P<m>\d{2})(?P<d>\d{2})"
        r"(?:[ T_-]*(?P<H>\d{2})(?P<M>\d{2})(?P<S>\d{2})?)?"
    ),
    re.compile(r"(?<![\d])(?P<m>\d{1,2})[-_.月](?P<d>\d{1,2})日?(?![\d])"),
]

TIME_RES = [
    re.compile(r"(?<!\d)(?P<H>\d{1,2})[-_.:：](?P<M>\d{2})(?:[-_.:：](?P<S>\d{2}))?(?!\d)"),
]


def parse_datetime_from_name(
    stem: str, tz_name: str, fallback: datetime | None = None
) -> datetime | None:
    """Best-effort local wall-clock parsing from a recording filename."""
    now_local = datetime.now(local_zone(tz_name))
    for pattern in DATETIME_RES:
        match = pattern.search(stem)
        if not match:
            continue
        groups = match.groupdict()
        try:
            year = int(groups.get("y") or now_local.year)
            month = int(groups["m"])
            day = int(groups["d"])
            hour = int(groups.get("H") or 0)
            minute = int(groups.get("M") or 0)
            second = int(groups.get("S") or 0)
            if not groups.get("y"):
                candidate = datetime(year, month, day, hour, minute, second)
                if candidate.date() > now_local.date() + timedelta(days=1):
                    candidate = candidate.replace(year=year - 1)
                year = candidate.year
            parsed = datetime(year, month, day, hour, minute, second)
            if 2000 <= parsed.year <= now_local.year + 1:
                return local_to_utc(parsed, tz_name)
        except ValueError:
            continue
    if fallback is not None:
        return local_to_utc(fallback, tz_name)
    return None


STOP_TITLE_WORDS = {
    "预约",
    "复尺",
    "报价",
    "合同",
    "发票",
    "维修",
    "体检",
    "会议",
    "方案",
    "尺寸",
    "账单",
    "快递",
    "装修",
    "安装",
    "售后",
    "回访",
    "确认",
    "沟通",
    "咨询",
    "语音记录",
    "客户",
    "领导",
    "同事",
    "家人",
}


def _name_from_tokens(text: str) -> str | None:
    text = re.sub(r"[\（\(\[【].*?[\）\)\]】]", " ", text)
    text = re.sub(r"[_\-.]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return None
    for token in text.split(" "):
        token = token.strip(" -_.,，。")
        if not token:
            continue
        lower = token.lower()
        if any(generic in lower for generic in GENERIC_TOKENS):
            continue
        if token in STOP_TITLE_WORDS:
            continue
        if re.fullmatch(r"(19|20)\d{2}", token):
            continue
        if re.fullmatch(r"\d{1,4}", token):
            continue
        if CHINESE_NAME_RE.match(token):
            if token not in {"未知来电", "未知号码", "陌生人", "未接来电"}:
                return token
        elif LATIN_NAME_RE.match(token) and not re.fullmatch(
            r"(am|pm|mon|tue|wed|thu|fri|sat|sun)", lower
        ):
            return token.title()
    return None


def guess_contact_and_title(
    stem: str, tz_name: str
) -> tuple[str | None, str | None, str | None]:
    """Return (contact_name, phone, title). Conservative: only uses the filename."""
    phone_match = PHONE_RE.search(stem)
    phone = phone_match.group(1) if phone_match else None

    stripped = stem
    for pattern in DATETIME_RES:
        stripped = pattern.sub(" ", stripped)
    for pattern in TIME_RES:
        stripped = pattern.sub(" ", stripped)
    stripped = re.sub(r"[\（\(\[【]\s*\d+\s*[\）\)\]】]", " ", stripped)
    stripped = re.sub(r"[_\-.]+", " ", stripped)
    stripped = re.sub(r"\s+", " ", stripped).strip(" -_.")

    cleaned_tokens = [
        token
        for token in re.split(r"\s+", stripped)
        if token
        and not any(token.lower() in {g, g + "s"} for g in GENERIC_TOKENS)
        and not re.fullmatch(r"\d+", token)
    ]
    cleaned = " ".join(cleaned_tokens).strip()

    has_call_hint = any(hint in stem.lower() for hint in ("通话", "call", "dial"))
    candidate = _name_from_tokens(cleaned) if (has_call_hint or phone or "【" in stem) else None
    contact = candidate
    if contact and cleaned:
        remainder = cleaned.replace(contact, " ", 1).strip(" -_.,，。")
        title = remainder if len(remainder) >= 2 else None
    else:
        title = cleaned if len(cleaned) >= 2 else None

    if not contact and phone:
        contact = f"尾号 {phone[-4:]}"

    if title:
        title = title[:80]
    return contact, phone, title


def clean_title_from_stem(stem: str) -> str | None:
    _, _, title = guess_contact_and_title(stem, "Asia/Shanghai")
    return title


def ensure_list(value: Any) -> list[Any]:
    if isinstance(value, list):
        return value
    if value is None:
        return []
    return [value]


def truncate(text: str, length: int = 120) -> str:
    text = re.sub(r"\s+", " ", (text or "")).strip()
    if len(text) <= length:
        return text
    return text[: length - 1].rstrip("，。,. ") + "…"


def display_date(value: datetime | None, tz_name: str) -> str:
    local = utc_to_local(value, tz_name)
    if not local:
        return ""
    return local.strftime("%Y-%m-%d %H:%M")


def parse_date_only(value: str | None) -> date | None:
    if not value:
        return None
    try:
        return date.fromisoformat(value[:10])
    except ValueError:
        return None


def dedupe_keep_order(items: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    output: list[str] = []
    for item in items:
        key = item.strip()
        if key and key not in seen:
            seen.add(key)
            output.append(key)
    return output
