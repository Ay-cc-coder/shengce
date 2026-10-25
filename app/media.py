from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np


@dataclass
class AudioInfo:
    duration: float | None
    channels: int
    sample_rate: int
    peaks: list[int]


def _frame_float(frame) -> np.ndarray:  # type: ignore[no-untyped-def]
    array = frame.to_ndarray()
    if array.ndim == 1:
        array = array.reshape(1, -1)
    if np.issubdtype(array.dtype, np.integer):
        info = np.iinfo(array.dtype)
        scale = float(max(abs(info.min), info.max)) or 1.0
        array = array.astype(np.float32) / scale
    else:
        array = array.astype(np.float32)
    if array.shape[0] > 1:
        array = array.mean(axis=0, keepdims=True)
    return array


def analyse_audio(path: Path, bars: int = 96) -> AudioInfo:
    """Decode audio with PyAV, return duration and a compact RMS waveform."""
    try:
        import av
    except Exception as exc:  # pragma: no cover - dependency is in the image
        raise RuntimeError("缺少音频解码组件 PyAV") from exc

    chunks: list[float] = []
    sample_total = 0
    sample_rate = 0
    channels = 1
    duration: float | None = None

    with av.open(str(path)) as container:
        if not container.streams.audio:
            raise RuntimeError("文件里没有可读取的音轨")
        stream = container.streams.audio[0]
        sample_rate = int(stream.rate or 0)
        channels = int(stream.channels or 1)
        if container.duration:
            duration = float(container.duration) / 1_000_000.0
        elif stream.duration and stream.time_base:
            duration = float(stream.duration * stream.time_base)

        for frame in container.decode(stream):
            if frame.sample_rate:
                sample_rate = int(frame.sample_rate)
            array = _frame_float(frame)
            if array.size == 0:
                continue
            # Split very large frames into manageable RMS chunks.
            for start in range(0, array.shape[1], 2048):
                piece = array[:, start : start + 2048]
                if piece.size == 0:
                    continue
                rms = float(np.sqrt(np.mean(np.square(piece))))
                chunks.append(rms)
                sample_total += piece.shape[1]

    if duration is None and sample_rate:
        duration = sample_total / float(sample_rate)

    if not chunks:
        return AudioInfo(duration=duration, channels=channels, sample_rate=sample_rate, peaks=[])

    values = np.asarray(chunks, dtype=np.float32)
    # A high percentile keeps one loud click from flattening the whole waveform.
    ceiling = float(np.percentile(values, 96)) if values.size > 8 else float(values.max())
    if ceiling <= 1e-7:
        peaks = [0] * bars
    else:
        normalized = np.clip(values / ceiling, 0, 1)
        indices = np.linspace(0, len(normalized), bars + 1).astype(int)
        peaks = []
        for left, right in zip(indices[:-1], indices[1:]):
            piece = normalized[left:right]
            value = float(np.mean(piece)) if piece.size else 0.0
            # A gentle curve reads better at small heights than raw RMS.
            peaks.append(int(round(math.sqrt(max(value, 0.0)) * 100)))
    return AudioInfo(duration=duration, channels=channels, sample_rate=sample_rate, peaks=peaks)
