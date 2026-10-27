from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from ..runtime import apply_runtime, save_runtime
from ..system_info import cuda_device_count, nvidia_gpus, system_payload
from ..transcribe import reset_model

router = APIRouter(prefix="/api/system", tags=["system"])

ALLOWED_MODELS = {"base", "small", "medium", "large-v3", "large-v3-turbo"}


def _payload(request: Request) -> dict:
    return system_payload(
        request.app.state.db,
        request.app.state.settings,
        request.app.state.worker,
    )


@router.get("")
def get_system(request: Request) -> dict:
    return _payload(request)


class ASRUpdate(BaseModel):
    engine: str = Field(default="faster", pattern="^(faster|sensevoice)$")
    device: str = Field(default="cpu", pattern="^(cpu|cuda)$")
    device_index: int = Field(default=0, ge=0, le=16)
    model: Optional[str] = Field(default=None, max_length=40)


@router.post("/asr")
def update_asr(request: Request, body: ASRUpdate) -> dict:
    settings = request.app.state.settings
    if body.engine == "sensevoice":
        data = save_runtime(
            settings,
            engine="sensevoice",
            device="cpu",
            device_index=0,
            model="sensevoice-small",
            compute_type="int8",
        )
        apply_runtime(settings, data)
        reset_model()
        try:
            from ..sensevoice import reset_model as reset_sensevoice

            reset_sensevoice()
        except Exception:
            pass
        return _payload(request)
    model = (body.model or settings.whisper_model).strip()
    if model not in ALLOWED_MODELS:
        raise HTTPException(status_code=422, detail=f"不支持的模型：{model}")
    if body.device == "cuda":
        if not settings.asr_gpu_supported:
            raise HTTPException(
                status_code=400,
                detail="当前是 CPU 镜像，不能使用 GPU。请改用 docker-compose.gpu.yml 和 :cuda 镜像。",
            )
        gpus, error = nvidia_gpus()
        if not gpus or cuda_device_count() < 1:
            raise HTTPException(status_code=400, detail=error or "没有检测到可用的 NVIDIA GPU。")
        if body.device_index >= len(gpus):
            raise HTTPException(status_code=422, detail="选择的 GPU 序号不存在。")
    compute_type = "float16" if body.device == "cuda" else "int8"
    data = save_runtime(
        settings,
        engine="faster",
        device=body.device,
        device_index=body.device_index,
        model=model,
        compute_type=compute_type,
    )
    apply_runtime(settings, data)
    reset_model()
    return _payload(request)


class WorkerUpdate(BaseModel):
    paused: bool


@router.post("/worker")
def update_worker(request: Request, body: WorkerUpdate) -> dict:
    settings = request.app.state.settings
    worker = request.app.state.worker
    worker.set_paused(body.paused)
    if not body.paused and (worker.thread is None or not worker.thread.is_alive()):
        worker.start()
    save_runtime(settings, worker_paused=body.paused)
    return _payload(request)
