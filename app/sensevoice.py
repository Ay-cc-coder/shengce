from __future__ import annotations

import logging
import re
import threading
from pathlib import Path
from typing import Any

import httpx

from .config import Settings
from .transcribe import TranscriptSegment, Transcription

logger = logging.getLogger(__name__)

MODEL_URL = "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx"
TOKENS_URL = "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt"
PUNCTUATION = "。！？!?；;"

_recognizer: Any = None
_recognizer_key: tuple[str, int] | None = None
_model_lock = threading.Lock()


def _download(url: str, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    temp = target.with_suffix(target.suffix + ".part")
    logger.info("downloading SenseVoice model: %s", url)
    with httpx.Client(timeout=None, follow_redirects=True) as client:
        with client.stream("GET", url) as response:
            response.raise_for_status()
            with temp.open("wb") as handle:
                for chunk in response.iter_bytes(1024 * 1024):
                    if chunk:
                        handle.write(chunk)
    temp.replace(target)


def _ensure_model(settings: Settings) -> tuple[Path, Path]:
    directory = settings.data_dir / "models" / "sensevoice"
    model = directory / "model.int8.onnx"
    tokens = directory / "tokens.txt"
    if not model.exists() or model.stat().st_size < 10_000_000:
        _download(MODEL_URL, model)
    if not tokens.exists() or tokens.stat().st_size < 10_000:
        _download(TOKENS_URL, tokens)
    return model, tokens


def _recognizer_for(settings: Settings):
    global _recognizer, _recognizer_key
    model, tokens = _ensure_model(settings)
    threads = max(1, settings.whisper_cpu_threads)
    key = (str(model), threads)
    with _model_lock:
        if _recognizer is not None and _recognizer_key == key:
            return _recognizer
        import sherpa_onnx

        logger.info("loading SenseVoice model %s (cpu, %s threads)", model, threads)
        _recognizer = sherpa_onnx.OfflineRecognizer.from_sense_voice(
            model=str(model),
            tokens=str(tokens),
            num_threads=threads,
            use_itn=True,
            language="zh",
            debug=False,
        )
        _recognizer_key = key
        return _recognizer


def reset_model() -> None:
    global _recognizer, _recognizer_key
    with _model_lock:
        _recognizer = None
        _recognizer_key = None


def _decode_chunks(path: Path, chunk_seconds: int = 30):  # type: ignore[no-untyped-def]
    import av
    import numpy as np

    chunk_samples = max(1, int(16000 * chunk_seconds))
    buffer = np.empty(0, dtype=np.float32)
    offset = 0.0
    with av.open(str(path)) as container:
        if not container.streams.audio:
            raise RuntimeError("文件里没有可读取的音轨")
        stream = container.streams.audio[0]
        resampler = av.AudioResampler(format="flt", layout="mono", rate=16000)
        for frame in container.decode(stream):
            for output in resampler.resample(frame):
                array = output.to_ndarray().reshape(-1).astype(np.float32)
                if not array.size:
                    continue
                buffer = np.concatenate([buffer, array])
                while buffer.size >= chunk_samples:
                    yield buffer[:chunk_samples], offset
                    buffer = buffer[chunk_samples:]
                    offset += chunk_seconds
    if buffer.size:
        yield buffer, offset

def _segments_from_tokens(
    result: Any, duration: float, fallback_text: str
) -> list[TranscriptSegment]:
    tokens = list(getattr(result, "tokens", []) or [])
    timestamps = list(getattr(result, "timestamps", []) or [])
    if tokens and len(tokens) == len(timestamps):
        segments: list[TranscriptSegment] = []
        buffer: list[str] = []
        start = float(timestamps[0])
        last = start
        for token, timestamp in zip(tokens, timestamps):
            token = str(token)
            if token.startswith("<|") and token.endswith("|>"):
                continue
            timestamp = float(timestamp)
            if not buffer:
                start = timestamp
            buffer.append(token)
            last = timestamp
            if token in PUNCTUATION:
                text = "".join(buffer).strip()
                if text:
                    segments.append(
                        TranscriptSegment(
                            start=round(start, 2),
                            end=round(min(duration, last + 0.35), 2),
                            text=text,
                        )
                    )
                buffer = []
        if buffer:
            text = "".join(buffer).strip()
            if text:
                segments.append(
                    TranscriptSegment(
                        start=round(start, 2),
                        end=round(min(duration, last + 0.35), 2),
                        text=text,
                    )
                )
        if segments:
            return segments

    text = (fallback_text or "").strip()
    if not text:
        return []
    parts = [part.strip() for part in re.split(r"(?<=[。！？!?；;])\s*", text) if part.strip()]
    if not parts:
        return []
    total = sum(len(part) for part in parts)
    cursor = 0.0
    output: list[TranscriptSegment] = []
    for part in parts:
        length = max(1, len(part))
        span = duration * length / max(1, total)
        output.append(
            TranscriptSegment(
                start=round(cursor, 2),
                end=round(min(duration, cursor + span), 2),
                text=part,
            )
        )
        cursor += span
    return output


def transcribe_sensevoice(path: Path, settings: Settings) -> Transcription:
    recognizer = _recognizer_for(settings)
    segments: list[TranscriptSegment] = []
    texts: list[str] = []
    for samples, offset in _decode_chunks(path):
        stream = recognizer.create_stream()
        stream.accept_waveform(16000, samples)
        recognizer.decode_stream(stream)
        result = stream.result
        text = str(getattr(result, "text", "") or "").strip()
        chunk_duration = samples.size / 16000.0
        for segment in _segments_from_tokens(result, chunk_duration, text):
            segments.append(
                TranscriptSegment(
                    start=round(segment.start + offset, 2),
                    end=round(segment.end + offset, 2),
                    text=segment.text,
                )
            )
        if text:
            texts.append(text)
    full_text = " ".join(texts).strip()
    if not segments and full_text:
        segments = [TranscriptSegment(start=0.0, end=0.0, text=full_text)]
    return Transcription(
        segments=segments,
        language="zh",
        model="sensevoice-small",
        source="sensevoice",
        text=full_text or " ".join(segment.text for segment in segments),
    )
