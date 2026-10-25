from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


@pytest.fixture()
def settings(tmp_path: Path) -> Settings:
    return Settings(
        data_dir=tmp_path / "data",
        admin_password="test-pass",
        dav_username="audiowatch",
        dav_password="dav-pass",
        session_secret="test-session-secret",
        start_worker=False,
        asr_engine="fake",
        demo_mode=True,
        seed_demo=False,
        llm_api_key="",
    )


@pytest.fixture()
def app(settings: Settings):
    return create_app(settings)


@pytest.fixture()
def client(app):
    with TestClient(app) as test_client:
        response = test_client.post("/api/auth/login", json={"password": "test-pass"})
        assert response.status_code == 200
        yield test_client


@pytest.fixture()
def dav_auth() -> tuple[str, str]:
    return ("audiowatch", "dav-pass")
