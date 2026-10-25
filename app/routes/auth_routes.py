from __future__ import annotations

from fastapi import APIRouter, Request, Response
from pydantic import BaseModel

from ..auth import (
    COOKIE_NAME,
    check_password,
    clear_session_cookie,
    client_key,
    set_session_cookie,
    verify_session,
)

router = APIRouter(prefix="/api/auth", tags=["auth"])


class LoginBody(BaseModel):
    password: str


@router.get("/status")
def status(request: Request) -> dict:
    settings = request.app.state.settings
    token = request.cookies.get(COOKIE_NAME)
    return {
        "authenticated": verify_session(settings, token),
        "demo_mode": settings.demo_mode,
        "llm_enabled": settings.llm_enabled,
        "version": request.app.state.version,
    }


@router.post("/login")
def login(body: LoginBody, request: Request, response: Response) -> Response:
    from fastapi.responses import JSONResponse

    settings = request.app.state.settings
    limiter = request.app.state.limiter
    key = client_key(request)
    if not limiter.allowed(key):
        return JSONResponse(
            status_code=429,
            content={"detail": "尝试次数过多，请十分钟后再试。"},
        )
    if not check_password(settings, body.password):
        limiter.fail(key)
        return JSONResponse(status_code=401, content={"detail": "密码不正确。"})
    limiter.reset(key)
    result = JSONResponse(
        content={
            "authenticated": True,
            "demo_mode": settings.demo_mode,
        }
    )
    set_session_cookie(result, settings, request)
    return result


@router.post("/logout")
def logout() -> Response:
    from fastapi.responses import JSONResponse

    result = JSONResponse(content={"authenticated": False})
    clear_session_cookie(result)
    return result
