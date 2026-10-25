# 架构

## 进程与线程

```text
uvicorn (1 worker)
├── FastAPI / WebDAV / 静态站点
├── PipelineWorker        单线程处理队列
└── library scanner       每 300s 补收文件
```

- **单进程、单 worker**：SQLite + 本地文件 + 一个处理线程。不要开多个 uvicorn worker，否则会争抢队列和模型；如需扩展，先换 PostgreSQL/任务队列。
- **WebDAV** 与 WebUI 共用同一个 FastAPI 进程：`/dav/...` 走 Basic Auth，`/api/...` 走会话 Cookie。
- Caddy 只负责 TLS 和反向代理，不处理业务逻辑。

## 数据流

```text
PUT /dav/<path>
  └─ 流式写入 .upload-<uuid> → fsync → os.replace
       └─ upsert_file：解析文件名日期/联系人；入库 status=queued
            └─ PipelineWorker 领取
                 ├─ sha256 + 大小
                 ├─ 音频：PyAV 读取时长与 96 格波形
                 │    └─ faster-whisper 转写（首次下载模型）
                 │         └─ 按停顿切分对话 → 启发式左右说话人
                 │              └─ 本地规则或 LLM 摘要 → 待办
                 └─ 文档：pypdf / python-docx / 文本读取 → 分类标签
                      └─ status=ready
```

- 上传接口只做落盘和登记，不等待转写；手机 PUT 可以快速返回。
- 处理线程每次只领一个 `queued`，用 `status` 行做轻量队列；启动时把所有 `processing` 重置为 `queued`。
- 扫描线程每 5 分钟遍历 `library/`，把绕过 WebDAV 直接复制进来的文件登记入队；它比较 `size + mtime`，不会重复处理未变化文件。
- WebDAV 探针（`audiowatch-connection-test-*.txt`）、隐藏文件、临时文件在登记前就被忽略。

## 数据库

SQLite 位于 `data/shengce.db`，启动时 `create_all` 建表，启用 WAL 与外键。

| 表 | 作用 |
| --- | --- |
| `files` | 文件元数据、分类、处理状态、摘要、要点、主题、说话人映射、波形、时间 |
| `segments` | 对话的每一段：起止时间、说话人 key、文本 |
| `contacts` | 联系人、电话、头像颜色 |
| `actions` | 待办：文本、原话、截止日期、优先级、完成状态、来源段 |

`files.rel_path` 唯一；`files.contact_id` 为 `SET NULL`；`segments` / `actions` 随文件级联删除。

## 状态机

```text
queued ──► processing ──► ready
                │
                └────────► failed ──(重新整理)──► queued
```

`stage` 细分：`waiting`、`reading`、`classifying`、`transcribing`、`organizing`、`done`、`error`。UI 根据 `stage` 显示进度，不显示假进度条。

## 转写与说话人

- 默认 `faster-whisper`，`language=zh`，开启 VAD，`beam_size=5`。
- 模型缓存在 `data/models/`。
- faster-whisper 不做说话人分离。`conversation.py` 按停顿（≥0.72s）、句末语气和单段长度切 turn，然后交替标记说话人 1/2。
- 说话人映射存 `files.speakers` JSON，例如 `{"1":"陈岚","2":"我"}`；详情页可改名或交换。
- 语音备忘按单说话人 `me` 处理。

## 摘要与待办

两条路径：

1. **本机规则**（默认）：主题关键词、句子打分、请求/承诺句式、中文日期解析。不联网。
2. **OpenAI 兼容模型**：配置 `LLM_API_KEY` 后启用；输出 JSON，校验失败自动回退本机规则。只发送当前录音的转写文本、文件名、联系人和日期。

LLM 输出的待办必须带原句，服务端会把原句匹配回 segment，得到时间码；匹配不到则允许无时间码。

## 认证

- WebUI：单密码登录，HMAC-SHA256 签名的 HttpOnly Cookie，默认 30 天；失败次数限制在内存里。
- WebDAV：HTTP Basic Auth；账号密码独立于管理台。
- Caddy 在 HTTPS 下设置 `X-Forwarded-Proto`，应用据此决定 Cookie 是否加 `Secure`。
- 默认没有开放 `/api/health` 以外的匿名接口；静态登录页除外。

## 媒体与 Range

- 音频通过 `FileResponse` 返回，Starlette 处理 `Range`，支持浏览器拖动进度。
- 波形是入库时用 PyAV 解码后算出的 96 个 RMS 桶，前端只做展示和点击定位，不在浏览器里解码整段音频。
- 原始文件不转码；播放兼容性取决于浏览器对 m4a/mp3/wav 等的支持。

## 部署边界

- 容器内端口固定 8080；默认映射到宿主 3000（`APP_PORT=3000`）。TLS profile 用 Caddy 监听 80/443。
- `data/` 是唯一需要持久化的目录：数据库、音频、模型、密钥都在里面。
- 容器以 root 启动，chown `/data` 后用 `gosu` 降权到 `appuser`；裸机开发可直接用普通用户。
- 单文件上限 512 MB（可调）；前端和 WebDAV 都检查。
- 不内置备份任务；备份 = 停止容器 + 复制 `data/`。

## 失败与恢复

| 场景 | 行为 |
| --- | --- |
| 模型未下载 / 网络失败 | 文件 `failed`，错误写进 `error`；UI 显示原因，可重试 |
| 音频损坏 | PyAV 报错，文件保持可下载，状态 `failed` |
| 容器重启时正在处理 | 启动时重置为 `queued`，重新处理 |
| 手机重复 PUT 同名文件 | 覆盖并重新排队 |
| 探针文件 | 只落盘供 DELETE，不登记、不处理 |
| 资料库文件被删 | 数据库保留记录，播放时返回 404；扫描不会自动删记录 |
