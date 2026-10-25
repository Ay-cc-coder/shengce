from __future__ import annotations

from fastapi.testclient import TestClient


def test_propfind_root(client: TestClient, dav_auth) -> None:
    response = client.request(
        "PROPFIND",
        "/dav/",
        auth=dav_auth,
        headers={"Depth": "0"},
    )
    assert response.status_code == 207
    assert "<d:multistatus" in response.text
    assert "<d:collection/>" in response.text


def test_webdav_requires_auth(client: TestClient) -> None:
    response = client.request("PROPFIND", "/dav/", headers={"Depth": "0"})
    assert response.status_code == 401
    assert "www-authenticate" in response.headers


def test_put_mkcol_delete_and_probe_ignored(client: TestClient, dav_auth) -> None:
    before = client.get("/api/files?page_size=100").json()["total"]

    mkcol = client.request("MKCOL", "/dav/测试目录", auth=dav_auth)
    assert mkcol.status_code == 201

    put = client.put(
        "/dav/测试目录/hello.txt",
        content="hello".encode("utf-8"),
        auth=dav_auth,
    )
    assert put.status_code == 201
    assert (client.app.state.settings.library_dir / "测试目录" / "hello.txt").exists()

    listing = client.get("/api/files?page_size=100").json()
    assert listing["total"] == before + 1

    delete = client.delete("/dav/测试目录/hello.txt", auth=dav_auth)
    assert delete.status_code == 204
    after = client.get("/api/files?page_size=100").json()
    assert after["total"] == before

    probe = client.put(
        "/dav/audiowatch-connection-test-abc.txt",
        content=b"probe",
        auth=dav_auth,
    )
    assert probe.status_code == 201
    assert client.get("/api/files?page_size=100").json()["total"] == after["total"]
    assert client.delete("/dav/audiowatch-connection-test-abc.txt", auth=dav_auth).status_code == 204


def test_traversal_rejected(client: TestClient, dav_auth) -> None:
    response = client.put("/dav/..%2F..%2Fetc%2Fpasswd", content=b"x", auth=dav_auth)
    assert response.status_code in {400, 404, 409}
