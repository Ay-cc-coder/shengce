from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any

from .config import Settings

logger = logging.getLogger(__name__)


def _gpu_count() -> int:
    try:
        import ctranslate2

        return int(ctranslate2.get_cuda_device_count())
    except Exception:
        return 0


def runtime_path(settings: Settings) -> Path:
    return settings.data_dir / "runtime.json"


def default_runtime(settings: Settings) -> dict[str, Any]:
    return {
        "device": settings.whisper_device,
        "device_index": settings.whisper_device_index,
        "model": settings.whisper_model,
        "compute_type": settings.whisper_compute_type,
        "worker_paused": False,
    }


def _validated(settings: Settings, data: dict[str, Any]) -> dict[str, Any]:
    runtime = default_runtime(settings)
    runtime.update({key: data[key] for key in runtime if key in data})
    if runtime["device"] not in {"cpu", "cuda"}:
        runtime["device"] = "cpu"
    if runtime["device"] == "cuda":
        if not settings.asr_gpu_supported or _gpu_count() < 1:
            logger.warning("CUDA requested but unavailable; falling back to CPU")
            runtime["device"] = "cpu"
        else:
            runtime["compute_type"] = "float16"
    if runtime["device"] == "cpu":
        runtime["compute_type"] = "int8"
    try:
        runtime["device_index"] = max(0, int(runtime.get("device_index", 0)))
    except (TypeError, ValueError):
        runtime["device_index"] = 0
    runtime["worker_paused"] = bool(runtime.get("worker_paused", False))
    runtime["model"] = str(runtime.get("model") or settings.whisper_model)
    return runtime


def apply_runtime(settings: Settings, data: dict[str, Any]) -> dict[str, Any]:
    runtime = _validated(settings, data)
    settings.whisper_device = runtime["device"]
    settings.whisper_device_index = runtime["device_index"]
    settings.whisper_model = runtime["model"]
    settings.whisper_compute_type = runtime["compute_type"]
    return runtime


def load_runtime(settings: Settings) -> dict[str, Any]:
    path = runtime_path(settings)
    data = default_runtime(settings)
    if path.exists():
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                data.update(value)
        except Exception as exc:
            logger.warning("runtime config ignored: %s", type(exc).__name__)
    runtime = apply_runtime(settings, data)
    return runtime


def save_runtime(settings: Settings, **changes: Any) -> dict[str, Any]:
    path = runtime_path(settings)
    data = default_runtime(settings)
    if path.exists():
        try:
            existing = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(existing, dict):
                data.update(existing)
        except Exception:
            pass
    data.update(changes)
    data = _validated(settings, data)
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temp, path)
    try:
        path.chmod(0o600)
    except OSError:
        pass
    return data
