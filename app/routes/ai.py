from __future__ import annotations


from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from ..ai_classify import (
    apply_rules,
    delete_rule,
    generate_rules,
    list_rules,
    test_connection,
)
from ..ai_config import public_ai_config, save_ai_config

router = APIRouter(prefix="/api/ai", tags=["ai"])


@router.get("/config")
def get_ai_config(request: Request) -> dict:
    return public_ai_config(request.app.state.settings, request.app.state.ai_provider)


class AIConfigUpdate(BaseModel):
    provider: str = Field(default="custom", max_length=40)
    base_url: str = Field(min_length=1, max_length=300)
    api_key: str = Field(default="", max_length=400)
    model: str = Field(min_length=1, max_length=120)


@router.put("/config")
def update_ai_config(request: Request, body: AIConfigUpdate) -> dict:
    base_url = body.base_url.strip()
    if not (base_url.startswith("http://") or base_url.startswith("https://")):
        raise HTTPException(status_code=422, detail="服务器地址必须以 http:// 或 https:// 开头。")
    request.app.state.ai_provider = body.provider
    return save_ai_config(
        request.app.state.settings,
        base_url=base_url,
        api_key=body.api_key,
        model=body.model,
        provider=body.provider,
    )


@router.post("/test")
def test_ai(request: Request) -> dict:
    try:
        reply = test_connection(request.app.state.settings)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"连接失败：{exc}") from exc
    return {"ok": True, "reply": reply}


@router.get("/rules")
def get_rules(request: Request) -> dict:
    return {"items": list_rules(request.app.state.db)}


@router.post("/rules/generate")
def generate_ai_rules(request: Request) -> dict:
    try:
        return generate_rules(request.app.state.db, request.app.state.settings)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"生成规则失败：{exc}") from exc


@router.post("/rules/apply")
def apply_ai_rules(request: Request) -> dict:
    count = apply_rules(request.app.state.db)
    return {"ok": True, "changed": count, "items": list_rules(request.app.state.db)}


@router.delete("/rules/{rule_id}")
def remove_ai_rule(request: Request, rule_id: str) -> dict:
    if not delete_rule(request.app.state.db, rule_id):
        raise HTTPException(status_code=404, detail="规则不存在。")
    return {"ok": True, "items": list_rules(request.app.state.db)}
