from __future__ import annotations

import os
import secrets
from dataclasses import dataclass, field
from pathlib import Path


def _bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default


def _secret_file(path: Path, length: int = 32) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        value = path.read_text(encoding="utf-8").strip()
        if value:
            return value
    value = secrets.token_urlsafe(length)
    path.write_text(value + "\n", encoding="utf-8")
    try:
        path.chmod(0o600)
    except OSError:
        pass
    return value


@dataclass
class Settings:
    data_dir: Path = field(default_factory=lambda: Path(os.getenv("DATA_DIR", "/data")))
    tz: str = field(default_factory=lambda: os.getenv("TZ", "Asia/Shanghai"))
    admin_password: str = field(default_factory=lambda: os.getenv("ADMIN_PASSWORD", ""))
    dav_username: str = field(default_factory=lambda: os.getenv("DAV_USERNAME", "audiowatch"))
    dav_password: str = field(default_factory=lambda: os.getenv("DAV_PASSWORD", ""))
    session_secret: str = field(default_factory=lambda: os.getenv("SESSION_SECRET", ""))
    whisper_model: str = field(default_factory=lambda: os.getenv("WHISPER_MODEL", "small"))
    whisper_device: str = field(default_factory=lambda: os.getenv("WHISPER_DEVICE", "cpu"))
    whisper_compute_type: str = field(
        default_factory=lambda: os.getenv("WHISPER_COMPUTE_TYPE", "int8")
    )
    whisper_cpu_threads: int = field(default_factory=lambda: _int("WHISPER_CPU_THREADS", 2))
    whisper_language: str = field(default_factory=lambda: os.getenv("WHISPER_LANGUAGE", "zh"))
    whisper_prompt: str = field(
        default_factory=lambda: os.getenv(
            "WHISPER_PROMPT", "以下是普通话电话录音，请用简体中文转写。"
        )
    )
    asr_engine: str = field(default_factory=lambda: os.getenv("ASR_ENGINE", "faster"))
    llm_base_url: str = field(
        default_factory=lambda: os.getenv("LLM_BASE_URL", "https://api.deepseek.com/v1")
    )
    llm_api_key: str = field(default_factory=lambda: os.getenv("LLM_API_KEY", ""))
    llm_model: str = field(default_factory=lambda: os.getenv("LLM_MODEL", "deepseek-chat"))
    llm_timeout: float = field(default_factory=lambda: float(os.getenv("LLM_TIMEOUT", "75")))
    max_upload_mb: int = field(default_factory=lambda: _int("MAX_UPLOAD_MB", 512))
    start_worker: bool = field(default_factory=lambda: _bool("START_WORKER", True))
    seed_demo: bool = field(default_factory=lambda: _bool("SEED_DEMO", False))
    demo_mode: bool = field(default_factory=lambda: _bool("DEMO_MODE", False))
    show_dav_password: bool = field(default_factory=lambda: _bool("SHOW_DAV_PASSWORD", True))
    public_url: str = field(default_factory=lambda: os.getenv("PUBLIC_URL", ""))
    secure_cookies: bool = field(default_factory=lambda: _bool("SECURE_COOKIES", False))
    session_days: int = field(default_factory=lambda: _int("SESSION_DAYS", 30))

    def __post_init__(self) -> None:
        self.data_dir = Path(self.data_dir).resolve()
        self.data_dir.mkdir(parents=True, exist_ok=True)
        (self.data_dir / "library").mkdir(exist_ok=True)
        (self.data_dir / "incoming").mkdir(exist_ok=True)
        (self.data_dir / "models").mkdir(exist_ok=True)
        (self.data_dir / "demo").mkdir(exist_ok=True)

        if not self.admin_password:
            password_file = self.data_dir / "admin-password.txt"
            generated = not password_file.exists()
            self.admin_password = _secret_file(password_file, 9)
            if generated:
                print("=" * 62, flush=True)
                print("声册已生成管理员密码:", self.admin_password, flush=True)
                print("文件位置:", password_file, flush=True)
                print("可在 .env 设置 ADMIN_PASSWORD 覆盖。", flush=True)
                print("=" * 62, flush=True)

        if not self.dav_password:
            password_file = self.data_dir / "dav-password.txt"
            generated = not password_file.exists()
            self.dav_password = _secret_file(password_file, 9)
            if generated:
                print("WebDAV 初始密码:", self.dav_password, flush=True)
                print("文件位置:", password_file, flush=True)

        if not self.session_secret:
            self.session_secret = _secret_file(self.data_dir / "session-secret", 40)

        os.environ.setdefault("TZ", self.tz)

    @property
    def library_dir(self) -> Path:
        return self.data_dir / "library"

    @property
    def incoming_dir(self) -> Path:
        return self.data_dir / "incoming"

    @property
    def db_path(self) -> Path:
        return self.data_dir / "shengce.db"

    @property
    def max_upload_bytes(self) -> int:
        return self.max_upload_mb * 1024 * 1024

    @property
    def llm_enabled(self) -> bool:
        return bool(self.llm_api_key and self.llm_base_url and self.llm_model)

def load_settings() -> Settings:
    return Settings()
