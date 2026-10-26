from __future__ import annotations

import json
import logging
import re
import threading
from dataclasses import dataclass, field
from pathlib import Path

from .config import Settings

logger = logging.getLogger(__name__)

_model = None
_model_lock = threading.Lock()
_model_key: tuple[str, str, str, int, int] | None = None


@dataclass
class TranscriptSegment:
    start: float
    end: float
    text: str


@dataclass
class Transcription:
    segments: list[TranscriptSegment] = field(default_factory=list)
    language: str = "zh"
    model: str = ""
    source: str = "faster-whisper"
    text: str = ""


def _clean_text(text: str) -> str:
    text = re.sub(r"\s+", " ", (text or "")).strip()
    text = re.sub(r"^[\-–—·\s]+", "", text)
    try:
        from zhconv import convert

        text = convert(text, "zh-cn")
    except Exception:
        pass
    return text


def _load_model(settings: Settings):
    global _model, _model_key
    key = (
        settings.whisper_model,
        settings.whisper_device,
        settings.whisper_compute_type,
        settings.whisper_cpu_threads,
        settings.whisper_device_index,
    )
    with _model_lock:
        if _model is not None and _model_key == key:
            return _model
        from faster_whisper import WhisperModel

        logger.info(
            "loading whisper model %s (%s/%s, %s threads)",
            settings.whisper_model,
            settings.whisper_device,
            settings.whisper_compute_type,
            settings.whisper_cpu_threads,
        )
        _model = WhisperModel(
            settings.whisper_model,
            device=settings.whisper_device,
            compute_type=settings.whisper_compute_type,
            device_index=settings.whisper_device_index,
            cpu_threads=max(1, settings.whisper_cpu_threads),
            num_workers=1,
            download_root=str(settings.data_dir / "models"),
        )
        _model_key = key
        return _model


def reset_model() -> None:
    global _model, _model_key
    with _model_lock:
        _model = None
        _model_key = None


def _fake_transcription(path: Path, settings: Settings) -> Transcription:
    candidates = [
        path.with_suffix(".transcript.json"),
        path.with_suffix(".json"),
        settings.data_dir / "transcripts" / f"{path.stem}.json",
        Path("demo/data") / f"{path.stem}.json",
    ]
    for candidate in candidates:
        if not candidate.exists():
            continue
        try:
            payload = json.loads(candidate.read_text(encoding="utf-8"))
            segments = [
                TranscriptSegment(
                    start=float(item["start"]),
                    end=float(item["end"]),
                    text=_clean_text(str(item["text"])),
                )
                for item in payload.get("segments", [])
            ]
            text = " ".join(segment.text for segment in segments)
            return Transcription(
                segments=segments,
                language=str(payload.get("language", "zh")),
                model="fixture",
                source="fixture",
                text=text,
            )
        except Exception as exc:
            logger.warning("failed to read fixture %s: %s", candidate, exc)
    logger.warning("no transcript fixture for %s; using placeholder", path)
    return Transcription(
        segments=[
            TranscriptSegment(
                start=0.0,
                end=1.0,
                text="（这是测试转写。没有找到对应的转写样例文件。）",
            )
        ],
        language="zh",
        model="fixture",
        source="fixture",
        text="（这是测试转写。没有找到对应的转写样例文件。）",
    )


def transcribe_audio(path: Path, settings: Settings) -> Transcription:
    if settings.asr_engine == "fake":
        return _fake_transcription(path, settings)
    if settings.asr_engine == "off":
        return Transcription(segments=[], language="zh", model="off", source="off", text="")

    model = _load_model(settings)
    language = settings.whisper_language or None
    prompt = settings.whisper_prompt if language and language.startswith("zh") else None
    segments_iter, info = model.transcribe(
        str(path),
        language=language,
        initial_prompt=prompt or None,
        vad_filter=True,
        vad_parameters={"min_silence_duration_ms": 480},
        beam_size=5,
        temperature=0,
        condition_on_previous_text=True,
        word_timestamps=False,
    )
    segments: list[TranscriptSegment] = []
    for item in segments_iter:
        text = _clean_text(item.text)
        if not text:
            continue
        segments.append(
            TranscriptSegment(
                start=float(item.start),
                end=float(item.end),
                text=text,
            )
        )
    text = " ".join(segment.text for segment in segments)
    return Transcription(
        segments=segments,
        language=str(getattr(info, "language", settings.whisper_language) or "zh"),
        model=settings.whisper_model,
        source="faster-whisper",
        text=text,
    )
