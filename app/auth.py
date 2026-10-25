from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time
from collections import defaultdict, deque

from fastapi import Request
from starlette.responses import Response

from .config import Settings

COOKIE_NAME = "shengce_session"


def _b64encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _b64decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)


def _signature(secret: str, payload: str) -> str:
    digest = hmac.new(secret.encode("utf-8"), payload.encode("utf-8"), hashlib.sha256).digest()
    return _b64encode(digest)


def issue_session(settings: Settings, days: int | None = None) -> str:
    now = int(time.time())
    payload = {
        "iat": now,
        "exp": now + (days or settings.session_days) * 86400,
        "n": secrets.token_hex(6),
    }
    encoded = _b64encode(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    return f"{encoded}.{_signature(settings.session_secret, encoded)}"


def verify_session(settings: Settings, token: str | None) -> bool:
    if not token or "." not in token:
        return False
    encoded, signature = token.rsplit(".", 1)
    expected = _signature(settings.session_secret, encoded)
    if not hmac.compare_digest(signature, expected):
        return False
    try:
        payload = json.loads(_b64decode(encoded))
        return int(payload.get("exp", 0)) > int(time.time())
    except Exception:
        return False


def check_password(settings: Settings, supplied: str) -> bool:
    return bool(supplied) and hmac.compare_digest(supplied, settings.admin_password)


def request_is_https(request: Request) -> bool:
    forwarded = request.headers.get("x-forwarded-proto", "").split(",")[0].strip().lower()
    return forwarded == "https" or request.url.scheme == "https"


def set_session_cookie(response: Response, settings: Settings, request: Request) -> None:
    response.set_cookie(
        COOKIE_NAME,
        issue_session(settings),
        max_age=settings.session_days * 86400,
        httponly=True,
        samesite="lax",
        secure=request_is_https(request) or settings.secure_cookies,
        path="/",
    )


def clear_session_cookie(response: Response) -> None:
    response.delete_cookie(COOKIE_NAME, path="/")


class LoginLimiter:
    def __init__(self, max_attempts: int = 6, window: int = 600):
        self.max_attempts = max_attempts
        self.window = window
        self.attempts: dict[str, deque[float]] = defaultdict(deque)

    def _trim(self, key: str, now: float) -> None:
        bucket = self.attempts[key]
        while bucket and now - bucket[0] > self.window:
            bucket.popleft()

    def allowed(self, key: str) -> bool:
        now = time.time()
        self._trim(key, now)
        return len(self.attempts[key]) < self.max_attempts

    def fail(self, key: str) -> None:
        self.attempts[key].append(time.time())

    def reset(self, key: str) -> None:
        self.attempts.pop(key, None)


def client_key(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for", "").split(",")[0].strip()
    return forwarded or (request.client.host if request.client else "unknown")
