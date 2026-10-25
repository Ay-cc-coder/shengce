from __future__ import annotations

import base64
import email.utils
import mimetypes
import os
import uuid
from pathlib import Path
from urllib.parse import quote
from xml.sax.saxutils import escape

from fastapi import APIRouter, HTTPException, Request, Response
from fastapi.responses import FileResponse
from starlette.concurrency import run_in_threadpool

from .ingest import upsert_file
from .models import FileRecord
from .utils import is_probe_file, resolve_within, safe_rel_path

router = APIRouter(tags=["webdav"])

ALLOWED_METHODS = "OPTIONS, GET, HEAD, PROPFIND, PUT, DELETE, MKCOL"
DAV_NS = 'xmlns:d="DAV:"'


def _unauthorized() -> Response:
    return Response(
        status_code=401,
        content="Authentication required",
        headers={"WWW-Authenticate": 'Basic realm="Shengce WebDAV", charset="UTF-8"'},
    )


def _check_auth(request: Request) -> bool:
    settings = request.app.state.settings
    header = request.headers.get("authorization", "")
    if not header.lower().startswith("basic "):
        return False
    try:
        raw = base64.b64decode(header.split(" ", 1)[1]).decode("utf-8")
    except Exception:
        return False
    if ":" not in raw:
        return False
    username, password = raw.split(":", 1)
    import hmac

    return hmac.compare_digest(username, settings.dav_username) and hmac.compare_digest(
        password, settings.dav_password
    )


def _disk_path(request: Request, raw_path: str) -> tuple[Path, str]:
    settings = request.app.state.settings
    try:
        rel_path = safe_rel_path(raw_path)
        target = resolve_within(settings.library_dir, rel_path)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid path") from exc
    return target, rel_path


def _href(rel_path: str, is_dir: bool) -> str:
    encoded = "/".join(quote(part, safe="") for part in rel_path.split("/") if part)
    href = "/dav/" + encoded
    if is_dir and not href.endswith("/"):
        href += "/"
    return href


def _prop_response(path: Path, rel_path: str, is_dir: bool) -> str:
    stat = path.stat()
    modified = email.utils.formatdate(stat.st_mtime, usegmt=True)
    name = path.name if rel_path else "录音"
    href = escape(_href(rel_path, is_dir))
    etag = f'"{int(stat.st_mtime)}-{stat.st_size}"'
    if is_dir:
        resource_type = "<d:resourcetype><d:collection/></d:resourcetype>"
        content_type = "httpd/unix-directory"
        length = 0
    else:
        resource_type = "<d:resourcetype/>"
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        length = stat.st_size
    return f"""<d:response>
<d:href>{href}</d:href>
<d:propstat>
<d:prop>
<d:displayname>{escape(name)}</d:displayname>
{resource_type}
<d:getcontentlength>{length}</d:getcontentlength>
<d:getcontenttype>{escape(content_type)}</d:getcontenttype>
<d:getlastmodified>{modified}</d:getlastmodified>
<d:getetag>{escape(etag)}</d:getetag>
</d:prop>
<d:status>HTTP/1.1 200 OK</d:status>
</d:propstat>
</d:response>"""


async def _propfind(request: Request, raw_path: str) -> Response:
    target, rel_path = _disk_path(request, raw_path)
    if not target.exists():
        return Response(status_code=404, content="Not found")
    depth = request.headers.get("depth", "0").strip()
    parts = [_prop_response(target, rel_path, target.is_dir())]
    if target.is_dir() and depth != "0":
        try:
            entries = sorted(os.scandir(target), key=lambda entry: entry.name.lower())
        except OSError:
            entries = []
        for entry in entries:
            if entry.name.startswith(".upload-"):
                continue
            child_rel = f"{rel_path}/{entry.name}".strip("/")
            parts.append(_prop_response(Path(entry.path), child_rel, entry.is_dir()))
    xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        f"<d:multistatus {DAV_NS}>\n" + "\n".join(parts) + "\n</d:multistatus>"
    )
    return Response(
        content=xml,
        status_code=207,
        media_type="application/xml; charset=utf-8",
        headers={"DAV": "1, 2"},
    )


def _mkcol(request: Request, raw_path: str) -> Response:
    target, rel_path = _disk_path(request, raw_path)
    if not rel_path:
        return Response(status_code=405, content="Collection exists")
    if target.exists():
        return Response(status_code=405, content="Collection exists")
    if not target.parent.exists():
        return Response(status_code=409, content="Parent collection missing")
    try:
        target.mkdir()
    except OSError:
        return Response(status_code=507, content="Cannot create collection")
    return Response(status_code=201, headers={"Location": _href(rel_path, True)})


async def _put(request: Request, raw_path: str) -> Response:
    settings = request.app.state.settings
    db = request.app.state.db
    target, rel_path = _disk_path(request, raw_path)
    if not rel_path:
        return Response(status_code=405, content="Cannot PUT a collection")
    if not target.parent.exists():
        return Response(status_code=409, content="Parent collection missing")
    try:
        declared = int(request.headers.get("content-length", "0") or "0")
    except ValueError:
        declared = 0
    if declared > settings.max_upload_bytes:
        return Response(status_code=413, content="File too large")

    temp = target.parent / f".upload-{uuid.uuid4().hex}"
    size = 0
    try:
        with temp.open("wb") as handle:
            async for chunk in request.stream():
                if not chunk:
                    continue
                size += len(chunk)
                if size > settings.max_upload_bytes:
                    raise HTTPException(status_code=413, detail="File too large")
                handle.write(chunk)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, target)
    except HTTPException:
        temp.unlink(missing_ok=True)
        return Response(status_code=413, content="File too large")
    except OSError:
        temp.unlink(missing_ok=True)
        return Response(status_code=507, content="Cannot write file")
    except Exception:
        temp.unlink(missing_ok=True)
        raise

    if not is_probe_file(target.name):
        await run_in_threadpool(
            upsert_file, db, target, rel_path, "webdav", True, None
        )
    return Response(
        status_code=201,
        headers={"ETag": f'"{int(target.stat().st_mtime)}-{size}"'},
    )


async def _delete(request: Request, raw_path: str) -> Response:
    db = request.app.state.db
    target, rel_path = _disk_path(request, raw_path)
    if not rel_path or not target.exists():
        return Response(status_code=404, content="Not found")
    if target.is_dir():
        try:
            target.rmdir()
        except OSError:
            return Response(status_code=409, content="Collection is not empty")
        return Response(status_code=204)
    with db.session() as session:
        record = session.query(FileRecord).filter(FileRecord.rel_path == rel_path).first()
        if record:
            session.delete(record)
    try:
        target.unlink()
    except OSError:
        return Response(status_code=507, content="Cannot delete file")
    return Response(status_code=204)


@router.api_route("/dav", methods=["OPTIONS", "GET", "HEAD", "PROPFIND", "PUT", "DELETE", "MKCOL"])
@router.api_route("/dav/{raw_path:path}", methods=["OPTIONS", "GET", "HEAD", "PROPFIND", "PUT", "DELETE", "MKCOL"])
async def dav_endpoint(request: Request, raw_path: str = "") -> Response:
    if request.method == "OPTIONS":
        return Response(
            status_code=200,
            headers={"DAV": "1, 2", "MS-Author-Via": "DAV", "Allow": ALLOWED_METHODS},
        )
    if not _check_auth(request):
        return _unauthorized()

    if request.method == "PROPFIND":
        return await _propfind(request, raw_path)
    if request.method == "MKCOL":
        return _mkcol(request, raw_path)
    if request.method == "PUT":
        return await _put(request, raw_path)
    if request.method == "DELETE":
        return await _delete(request, raw_path)

    target, rel_path = _disk_path(request, raw_path)
    if not target.exists():
        return Response(status_code=404, content="Not found")
    if target.is_dir():
        return Response(status_code=405, content="Is a collection")
    mime = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
    return FileResponse(
        target,
        media_type=mime,
        headers={"Accept-Ranges": "bytes", "DAV": "1"},
    )
