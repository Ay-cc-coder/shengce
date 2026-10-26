from __future__ import annotations

from fastapi.testclient import TestClient

from app.pipeline import process_file


def test_health_is_public(client: TestClient) -> None:
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json()["ok"] is True


def test_api_requires_login(app) -> None:
    with TestClient(app) as anonymous:
        response = anonymous.get("/api/overview")
        assert response.status_code == 401
        assert response.json()["detail"] == "请先登录。"


def test_login_rejects_wrong_password(app) -> None:
    with TestClient(app) as anonymous:
        response = anonymous.post("/api/auth/login", json={"password": "nope"})
        assert response.status_code == 401


def test_seeded_overview_and_stats(client: TestClient) -> None:
    overview = client.get("/api/overview")
    assert overview.status_code == 200
    payload = overview.json()
    assert payload["latest"]
    assert payload["latest"]["kind"] == "voice" or payload["latest"]["segments"]
    assert payload["total_recordings"] == 13
    assert payload["actions"]

    stats = client.get("/api/stats?days=30").json()
    assert stats["total_calls"] == 11
    assert stats["top_contacts"][0]["contact"]["name"] == "陈岚"
    assert stats["top_contacts"][0]["calls"] == 3


def test_recording_detail_chat_and_search(client: TestClient) -> None:
    listing = client.get("/api/recordings?kind=call&page_size=5").json()
    assert listing["total"] == 11
    recording = listing["items"][0]
    detail = client.get(f"/api/recordings/{recording['id']}").json()
    assert detail["segments"]
    assert detail["summary"]
    assert detail["speakers"]
    search = client.get("/api/recordings?q=台面&page_size=50").json()
    assert search["total"] >= 1


def test_audio_range_request(client: TestClient) -> None:
    listing = client.get("/api/recordings?page_size=50").json()
    audio = next(item for item in listing["items"] if item["has_audio"])
    response = client.get(
        f"/api/recordings/{audio['id']}/audio",
        headers={"Range": "bytes=0-255"},
    )
    assert response.status_code == 206
    assert len(response.content) == 256
    assert response.headers["content-range"].startswith("bytes 0-255/")


def test_speaker_update_and_contact(client: TestClient) -> None:
    listing = client.get("/api/recordings?kind=call&page_size=1").json()
    recording = listing["items"][0]
    updated = client.patch(
        f"/api/recordings/{recording['id']}/speakers",
        json={"names": {"1": "对方", "2": "我"}},
    )
    assert updated.status_code == 200
    assert updated.json()["speakers"]["1"] == "对方"
    assert updated.json()["speaker_mode"] == "manual"

    contact = client.patch(
        f"/api/recordings/{recording['id']}",
        json={"contact_name": "测试联系人"},
    )
    assert contact.status_code == 200
    assert contact.json()["contact"]["name"] == "测试联系人"


def test_action_toggle(client: TestClient) -> None:
    actions = client.get("/api/actions?status=open").json()
    assert actions["open_count"] > 0
    action = actions["items"][0]
    done = client.patch(f"/api/actions/{action['id']}", json={"done": True})
    assert done.status_code == 200
    assert done.json()["item"]["done"] is True
    reopened = client.patch(f"/api/actions/{action['id']}", json={"done": False})
    assert reopened.json()["item"]["done"] is False


def test_upload_text_and_process(client: TestClient, app) -> None:
    files = {"file": ("报价单.txt", "合同报价单 甲方 乙方 项目金额 120000 元".encode("utf-8"), "text/plain")}
    response = client.post("/api/upload", files=files)
    assert response.status_code == 200
    item = response.json()["item"]
    assert item["kind"] == "document"

    process_file(app.state.db, app.state.settings, item["id"])
    detail = client.get("/api/files?q=报价单").json()
    assert detail["items"]
    assert detail["items"][0]["status"] == "ready"
    assert detail["items"][0]["category"] == "合同与报价"


def test_stats_range(client: TestClient) -> None:
    stats = client.get("/api/stats?days=7").json()
    assert stats["range_days"] == 7
    assert stats["total_calls"] >= 1
    assert len(stats["daily"]) == 7
    assert len(stats["hours"]) == 24


def test_setup_info(client: TestClient) -> None:
    setup = client.get("/api/setup").json()
    assert setup["dav_url"].endswith("/dav/")
    assert setup["dav_username"] == "audiowatch"
    assert setup["dav_password"] == "dav-pass"


def test_filename_date_and_contact_are_used(client: TestClient) -> None:
    files = {
        "file": (
            "通话录音 陈岚 2025-10-20 18-32-10.m4a",
            b"not real audio",
            "audio/mp4",
        )
    }
    response = client.post("/api/upload", files=files)
    assert response.status_code == 200
    item = response.json()["item"]
    assert item["recorded_at"] == "2025-10-20T10:32:10Z"
    assert item["contact"]["name"] == "陈岚"


def test_system_page_reports_cpu_and_queue(client: TestClient) -> None:
    payload = client.get("/api/system").json()
    assert payload["asr"]["device"] == "cpu"
    assert payload["asr"]["gpu_supported"] is False
    assert payload["queue"]["queued"] == 0
    assert "cpu_percent" in payload["resources"]

    paused = client.post("/api/system/worker", json={"paused": True})
    assert paused.status_code == 200
    assert paused.json()["worker"]["paused"] is True


def test_system_rejects_gpu_on_cpu_image(client: TestClient) -> None:
    response = client.post(
        "/api/system/asr",
        json={"device": "cuda", "device_index": 0, "model": "small"},
    )
    assert response.status_code == 400
    assert "CPU 镜像" in response.json()["detail"]

    response = client.post(
        "/api/system/asr",
        json={"device": "cpu", "device_index": 0, "model": "base"},
    )
    assert response.status_code == 200
    assert response.json()["asr"]["model"] == "base"


def test_ai_config_and_rule_application(client: TestClient) -> None:
    saved = client.put(
        "/api/ai/config",
        json={
            "provider": "custom",
            "base_url": "https://example.com/v1",
            "api_key": "sk-test-1234",
            "model": "test-model",
        },
    )
    assert saved.status_code == 200
    assert saved.json()["has_key"] is True
    assert saved.json()["key_hint"].endswith("1234")

    from app.models import ClassificationRule

    with client.app.state.db.session() as session:
        session.add(
            ClassificationRule(
                match="陈岚",
                kind="call",
                category="AI 测试分类",
                title="AI 测试标题",
                enabled=True,
                source="manual",
            )
        )
    applied = client.post("/api/ai/rules/apply")
    assert applied.status_code == 200
    assert applied.json()["changed"] >= 1
    rules = client.get("/api/ai/rules").json()["items"]
    assert any(rule["match"] == "陈岚" for rule in rules)


def test_ai_base_url_normalization() -> None:
    from app.ai_classify import _api_bases

    assert _api_bases("https://ai.superdoor.top") == [
        "https://ai.superdoor.top/v1",
        "https://ai.superdoor.top",
    ]
    assert _api_bases("https://api.deepseek.com/v1/") == [
        "https://api.deepseek.com/v1",
        "https://api.deepseek.com",
    ]
    assert _api_bases("http://192.168.5.221:11434/v1") == [
        "http://192.168.5.221:11434/v1",
        "http://192.168.5.221:11434",
    ]
