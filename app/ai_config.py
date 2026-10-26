from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any

from .config import Settings

logger = logging.getLogger(__name__)


def config_path(settings: Settings) -> Path:
    return settings.data_dir / "ai.json"


def load_ai_config(settings: Settings) -> dict[str, Any]:
    path = config_path(settings)
    data: dict[str, Any] = {}
    if path.exists():
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                data = value
        except Exception as exc:
            logger.warning("AI config ignored: %s", type(exc).__name__)
    if data.get("base_url"):
        settings.llm_base_url = str(data["base_url"]).strip()
    if data.get("api_key"):
        settings.llm_api_key = str(data["api_key"]).strip()
    if data.get("model"):
        settings.llm_model = str(data["model"]).strip()
    return public_ai_config(settings, data.get("provider") or "custom")


def public_ai_config(settings: Settings, provider: str = "custom") -> dict[str, Any]:
    key = settings.llm_api_key or ""
    return {
        "provider": provider,
        "base_url": settings.llm_base_url,
        "model": settings.llm_model,
        "has_key": bool(key),
        "key_hint": f"…{key[-4:]}" if len(key) >= 4 else "",
    }


def save_ai_config(
    settings: Settings,
    base_url: str,
    api_key: str,
    model: str,
    provider: str = "custom",
) -> dict[str, Any]:
    path = config_path(settings)
    existing: dict[str, Any] = {}
    if path.exists():
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                existing = value
        except Exception:
            pass
    key = api_key.strip() or str(existing.get("api_key") or settings.llm_api_key or "")
    data = {
        "provider": provider or "custom",
        "base_url": base_url.strip().rstrip("/"),
        "api_key": key,
        "model": model.strip(),
    }
    settings.llm_base_url = data["base_url"]
    settings.llm_api_key = key
    settings.llm_model = data["model"]
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temp, path)
    try:
        path.chmod(0o600)
    except OSError:
        pass
    return public_ai_config(settings, data["provider"])
