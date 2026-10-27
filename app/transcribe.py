from __future__ import annotations

import json
import logging
import re
import shutil
import subprocess
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

from .config import Settings

logger = logging.getLogger(__name__)

_model = None
_model_lock = threading.Lock()
_model_key: tuple[str, str, str, int, int] | None = None
_temp_checked_at = 0.0
_temp_value: float | None = None
_temp_lock = threading.Lock()


class ThermalPause(Exception):
    """Raised when the GPU is too hot to continue a transcription."""


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


def _gpu_temperature(settings: Settings) -> float | None:
    global _temp_checked_at, _temp_value
    if settings.whisper_device != "cuda":
        return None
    with _temp_lock:
        now = time.monotonic()
        if now - _temp_checked_at < 5:
            return _temp_value
    executable = shutil.which("nvidia-smi")
    if not executable:
        return None
    try:
        result = subprocess.run(
            [
                executable,
                "--query-gpu=temperature.gpu",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=8,
        )
        value: float | None = float(result.stdout.strip().splitlines()[0])
    except (OSError, subprocess.TimeoutExpired, ValueError, IndexError):
        value = None
    with _temp_lock:
        if value is not None:
            _temp_value = value
        _temp_checked_at = time.monotonic()
    return value


def _ensure_cool_enough(settings: Settings) -> None:
    temperature = _gpu_temperature(settings)
    if temperature is not None and temperature >= settings.gpu_temp_pause:
        raise ThermalPause(
            f"GPU 温度 {temperature:.0f}°C，达到 {settings.gpu_temp_pause}°C，暂停降温"
        )


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


PROMPT_LEAK_MARKERS = ("请用简体中文转写", "以下是普通话电话录音")


def _looks_like_prompt(text: str, prompt: str | None) -> bool:
    normalized = _clean_text(text).replace(" ", "")
    if not normalized:
        return False
    if prompt:
        prompt_normalized = _clean_text(prompt).replace(" ", "")
        if prompt_normalized and (
            normalized in prompt_normalized or prompt_normalized in normalized
        ):
            return True
    return any(marker in normalized for marker in PROMPT_LEAK_MARKERS)


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
    if settings.asr_engine == "sensevoice":
        from .sensevoice import transcribe_sensevoice

        return transcribe_sensevoice(path, settings)

    _ensure_cool_enough(settings)
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
        compression_ratio_threshold=2.2,
        no_speech_threshold=0.6,
        condition_on_previous_text=False,
        word_timestamps=False,
    )
    segments: list[TranscriptSegment] = []
    for item in segments_iter:
        _ensure_cool_enough(settings)
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
    if segments:
        leaked = sum(1 for segment in segments if _looks_like_prompt(segment.text, prompt))
        if leaked / len(segments) >= 0.6:
            logger.warning(
                "discarding %s/%s segments that repeat the initial prompt",
                leaked,
                len(segments),
            )
            segments = [segment for segment in segments if not _looks_like_prompt(segment.text, prompt)]
            if not segments:
                raise RuntimeError("未检测到有效语音：模型重复了提示词，请重新整理或检查音频音量。")
    text = " ".join(segment.text for segment in segments)
    return Transcription(
        segments=segments,
        language=str(getattr(info, "language", settings.whisper_language) or "zh"),
        model=settings.whisper_model,
        source="faster-whisper",
        text=text,
    )
