from __future__ import annotations

import csv
import io
import os
import shutil
import subprocess
import threading
import time
from pathlib import Path
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import selectinload

from .config import Settings
from .db import Database
from .models import FileRecord, utcnow
from .pipeline import PipelineWorker
from .utils import iso_utc

CGROUP = Path("/sys/fs/cgroup")
_last_cpu: tuple[float, float] | None = None
_cpu_lock = threading.Lock()
_gpu_cache: list[dict[str, Any]] = []
_gpu_cache_at: float = 0.0


def _read(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return None


def _host_memory() -> tuple[int, int]:
    total = available = 0
    try:
        for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
            if line.startswith("MemTotal:"):
                total = int(line.split()[1]) * 1024
            elif line.startswith("MemAvailable:"):
                available = int(line.split()[1]) * 1024
    except OSError:
        pass
    if not total:
        try:
            import psutil

            memory = psutil.virtual_memory()
            total, available = int(memory.total), int(memory.available)
        except Exception:
            pass
    return total, available


def _cpu_limit() -> float:
    raw = _read(CGROUP / "cpu.max")
    if raw:
        parts = raw.split()
        if len(parts) == 2 and parts[0] != "max":
            try:
                return max(0.1, int(parts[0]) / int(parts[1]))
            except (ValueError, ZeroDivisionError):
                pass
    v1_quota = _read(CGROUP / "cpu" / "cpu.cfs_quota_us")
    v1_period = _read(CGROUP / "cpu" / "cpu.cfs_period_us")
    if v1_quota and v1_period:
        try:
            quota = int(v1_quota)
            if quota > 0:
                return max(0.1, quota / int(v1_period))
        except ValueError:
            pass
    return float(os.cpu_count() or 1)


def _cpu_usage_usec() -> float:
    raw = _read(CGROUP / "cpu.stat")
    if raw:
        for line in raw.splitlines():
            if line.startswith("usage_usec "):
                try:
                    return float(line.split()[1])
                except ValueError:
                    return 0.0
    raw = _read(CGROUP / "cpuacct" / "cpuacct.usage")
    if raw:
        try:
            return float(raw) / 1000.0
        except ValueError:
            return 0.0
    return 0.0


def _memory() -> tuple[int, int]:
    current_raw = _read(CGROUP / "memory.current")
    max_raw = _read(CGROUP / "memory.max")
    if current_raw is None:
        current_raw = _read(CGROUP / "memory" / "memory.usage_in_bytes")
        max_raw = _read(CGROUP / "memory" / "memory.limit_in_bytes")
    try:
        used = int(current_raw or 0)
    except ValueError:
        used = 0
    try:
        limit = int(max_raw) if max_raw and max_raw != "max" else 0
    except ValueError:
        limit = 0
    host_total, _host_available = _host_memory()
    if used <= 0:
        try:
            import psutil

            used = int(psutil.Process().memory_info().rss)
        except Exception:
            pass
    if limit <= 0 or limit > host_total * 4:
        limit = host_total or used
    return used, limit


def container_resources() -> dict[str, Any]:
    global _last_cpu
    usage = _cpu_usage_usec()
    now = time.monotonic()
    with _cpu_lock:
        if _last_cpu is None:
            percent = 0.0
            core_usage = 0.0
        else:
            last_usage, last_time = _last_cpu
            elapsed = max(0.001, now - last_time)
            delta = max(0.0, usage - last_usage)
            core_usage = delta / 1_000_000.0 / elapsed
            percent = core_usage / _cpu_limit() * 100.0
        _last_cpu = (usage, now)
    used, limit = _memory()
    host_total, host_available = _host_memory()
    try:
        load = list(os.getloadavg())
    except OSError:
        load = [0.0, 0.0, 0.0]
    return {
        "cpu_percent": round(min(999.0, max(0.0, percent)), 1),
        "cpu_cores_used": round(max(0.0, core_usage), 2),
        "cpu_limit": round(_cpu_limit(), 2),
        "memory_used": used,
        "memory_limit": limit,
        "memory_percent": round(used / limit * 100.0, 1) if limit else 0.0,
        "host_memory_total": host_total,
        "host_memory_available": host_available,
        "host_memory_used": max(0, host_total - host_available),
        "load_1": round(load[0], 2),
        "load_5": round(load[1], 2),
        "load_15": round(load[2], 2),
    }


def cuda_device_count() -> int:
    try:
        import ctranslate2

        return int(ctranslate2.get_cuda_device_count())
    except Exception:
        return 0


def nvidia_gpus() -> tuple[list[dict[str, Any]], str | None]:
    global _gpu_cache, _gpu_cache_at
    executable = shutil.which("nvidia-smi")
    if not executable:
        return [], "当前容器中没有 nvidia-smi（CPU 镜像或未启用 GPU）"
    command = [
        executable,
        "--query-gpu=index,name,memory.total,memory.used,utilization.gpu,temperature.gpu,driver_version",
        "--format=csv,noheader,nounits",
    ]
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired) as exc:
        if _gpu_cache and time.time() - _gpu_cache_at < 120:
            return [dict(item) for item in _gpu_cache], f"nvidia-smi 暂时不可用（{type(exc).__name__}），显示最近一次结果"
        return [], f"nvidia-smi 调用失败：{type(exc).__name__}"
    if result.returncode != 0:
        if _gpu_cache and time.time() - _gpu_cache_at < 120:
            return [dict(item) for item in _gpu_cache], "nvidia-smi 暂时返回错误，显示最近一次结果"
        return [], "nvidia-smi 返回错误，容器可能没有 GPU 访问权限"
    gpus: list[dict[str, Any]] = []
    for row in csv.reader(io.StringIO(result.stdout)):
        if len(row) < 7:
            continue
        try:
            gpus.append(
                {
                    "index": int(row[0]),
                    "name": row[1].strip(),
                    "memory_total_mb": round(float(row[2])),
                    "memory_used_mb": round(float(row[3])),
                    "utilization_percent": round(float(row[4])),
                    "temperature_c": round(float(row[5])),
                    "driver_version": row[6].strip(),
                }
            )
        except ValueError:
            continue
    if gpus:
        _gpu_cache = [dict(item) for item in gpus]
        _gpu_cache_at = time.time()
    return gpus, None


def queue_info(db: Database) -> dict[str, Any]:
    with db.session() as session:
        queued = session.scalar(
            select(func.count()).select_from(FileRecord).where(FileRecord.status == "queued")
        ) or 0
        processing = session.scalar(
            select(func.count())
            .select_from(FileRecord)
            .where(FileRecord.status == "processing")
        ) or 0
        failed = session.scalar(
            select(func.count()).select_from(FileRecord).where(FileRecord.status == "failed")
        ) or 0
        current = session.scalar(
            select(FileRecord)
            .where(FileRecord.status == "processing")
            .order_by(FileRecord.uploaded_at.asc())
            .limit(1)
            .options(selectinload(FileRecord.contact))
        )
        current_payload = None
        if current:
            current_payload = {
                "id": current.id,
                "title": current.title or current.name,
                "name": current.name,
                "stage": current.stage,
            }
    return {
        "queued": queued,
        "processing": processing,
        "failed": failed,
        "current": current_payload,
    }


def system_payload(
    db: Database, settings: Settings, worker: PipelineWorker | None
) -> dict[str, Any]:
    gpus, gpu_error = nvidia_gpus()
    cuda_count = cuda_device_count()
    if not gpus and cuda_count > 0:
        gpus = [
            {
                "index": 0,
                "name": "NVIDIA GPU",
                "memory_total_mb": 0,
                "memory_used_mb": 0,
                "utilization_percent": 0,
                "temperature_c": 0,
                "driver_version": "unknown",
            }
        ]
        gpu_error = "nvidia-smi 不可用，但 CUDA 设备可用"
    gpu_supported = bool(settings.asr_gpu_supported and cuda_count > 0 and gpus)
    return {
        "asr": {
            "device": settings.whisper_device,
            "device_index": settings.whisper_device_index,
            "model": settings.whisper_model,
            "compute_type": settings.whisper_compute_type,
            "threads": settings.whisper_cpu_threads,
            "gpu_supported": gpu_supported,
            "gpu_image": settings.asr_gpu_supported,
        },
        "gpus": gpus,
        "gpu_error": gpu_error,
        "cuda_device_count": cuda_count,
        "intel_note": "Intel / AMD 核显暂不被 faster-whisper 使用；GPU 加速仅支持 NVIDIA。",
        "resources": container_resources(),
        "queue": queue_info(db),
        "worker": {
            "paused": bool(worker.is_paused()) if worker else False,
            "enabled": bool(
                worker
                and worker.thread
                and worker.thread.is_alive()
                and not worker.is_paused()
            ),
        },
        "timestamp": iso_utc(utcnow()),
    }
