# fnOS 安装

fnOS 的 Docker 支持 Compose。推荐使用已经构建好的镜像 `ghcr.io/ay-cc-coder/shengce:latest`，不要在 NAS 上从源码编译（转写依赖体积较大，NAS 上构建会慢很多）。

仓库同时保留源码构建方式；如果 GHCR 暂时不可用，可以退回 `docker-compose.yml`。

## 准备

1. 在 fnOS 的「应用中心」安装 Docker。
2. 打开 SSH，或使用 fnOS 的终端。
3. 确认 Compose 可用：

```bash
docker compose version
```

4. 选择一个存储池目录，例如 `/vol1/1000/docker/shengce`。`1000` 通常是第一个 fnOS 用户的 UID，可以用 `id` 查看；不同存储池可能是 `/vol2/...`。

## 方式一：拉取镜像（推荐）

```bash
sudo mkdir -p /vol1/1000/docker/shengce
sudo chown -R "$(id -u):$(id -g)" /vol1/1000/docker/shengce
cd /vol1/1000/docker/shengce
```

下载文件（`docker-compose.tls.yml` 和 `Caddyfile` 只有用 Caddy 时才需要）：

```bash
curl -fLO https://raw.githubusercontent.com/Ay-cc-coder/shengce/main/docker-compose.fnos.yml
curl -fLO https://raw.githubusercontent.com/Ay-cc-coder/shengce/main/.env.example
curl -fLO https://raw.githubusercontent.com/Ay-cc-coder/shengce/main/docker-compose.tls.yml
curl -fLO https://raw.githubusercontent.com/Ay-cc-coder/shengce/main/Caddyfile
mv .env.example .env
```

编辑 `.env`，至少改：

```dotenv
APP_PORT=3000
APP_BIND=0.0.0.0
ADMIN_PASSWORD=换成一个长密码
DAV_USERNAME=audiowatch
DAV_PASSWORD=换成一个长密码
TZ=Asia/Shanghai
```

启动：

```bash
docker compose -f docker-compose.fnos.yml pull
docker compose -f docker-compose.fnos.yml up -d
docker compose -f docker-compose.fnos.yml ps
```

打开 `http://fnOS的IP:3000`。首次转写会下载 Whisper 模型到 `./data/models/`。

## 方式二：克隆源码并构建

```bash
cd /vol1/1000/docker
git clone https://github.com/Ay-cc-coder/shengce.git
cd shengce
cp .env.example .env
# 修改 .env
docker compose up -d --build
```

源码构建的镜像名称是 `shengce:local`，后续更新需要重新 `--build`。

## 手机接入需要 HTTPS

「录音监控」只接受 HTTPS。WebUI 的 `http://IP:3000` 可以打开，但手机 WebDAV 测试会失败。

默认的 `docker-compose.fnos.yml` **只启动 app，不使用 80/443**。它只占用 `APP_PORT`（默认 3000）。HTTPS 有两种做法：

### 方式 A：复用 fnOS 已有反向代理（推荐）

fnOS 通常已经有 443 上的管理页面/反向代理，或者你装了 1Panel、Lucky、Nginx Proxy Manager 等。不要再启动 Caddy，直接把 HTTPS 域名代理到 app：

```text
https://record.example.com  →  http://127.0.0.1:3000
```

要点：

- 保留原始路径，**不要剥掉 `/dav/` 前缀**；
- 上传体积限制调到至少 512 MB；
- 关闭请求缓冲或把超时调大（WebDAV 大文件 PUT 需要）；
- 设置 `X-Forwarded-Proto: https`，否则登录 Cookie 不会被标记为 Secure；
- 证书用 fnOS/反代现有的 Let's Encrypt 证书即可，不需要 80/443 再给 Caddy。

如果反向代理本身跑在容器里，`127.0.0.1` 不一定指向宿主机；这时把代理目标改成宿主机的局域网 IP（如 `192.168.5.141:3000`）或两者共用的 Docker 网络地址。

然后在 `.env` 里把 app 收到本机回环：

```dotenv
APP_BIND=127.0.0.1
PUBLIC_URL=https://record.example.com
```

重启：

```bash
docker compose -f docker-compose.fnos.yml up -d --force-recreate
```

手机里填写 `https://record.example.com/dav/`，账号密码用 `.env` 里的 `DAV_USERNAME` / `DAV_PASSWORD`。

Nginx 示例（路径要落在 `/`，不要只转发 `/api`）：

```nginx
location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    client_max_body_size 512m;
    proxy_request_buffering off;
    proxy_read_timeout 300s;
}
```

### 方式 B：Caddy 使用 80/443（仅当端口空闲）

只有确认 fnOS 上没有服务占用 80/443 时，才叠加 TLS 文件：

```dotenv
DOMAIN=record.example.com
PUBLIC_URL=https://record.example.com
APP_BIND=127.0.0.1
```

```bash
docker compose -f docker-compose.fnos.yml -f docker-compose.tls.yml up -d
```

Caddy 会自动申请证书。如果 80/443 已被占用，**不要**强行启动这个文件；这不会因为改了 Caddy 端口就能自动签发证书，应该用方式 A，或使用 Cloudflare Tunnel / Tailscale 之类不占本机 80/443 的入口。

### 如果 80/443 被占用又没有反代

可选：

- 安装 1Panel / Lucky / Nginx Proxy Manager，用它们现有的 443 和证书；
- 用 Cloudflare Tunnel 或 Tailscale Serve 提供受信任的 HTTPS 入口；
- 不建议用自签名证书：iOS 插件不会绕过校验。

手机端只需要一个受信任的 HTTPS 地址，不要求这个地址由本项目的 Caddy 提供。

## 更新

```bash
cd /vol1/1000/docker/shengce
docker compose -f docker-compose.fnos.yml pull
docker compose -f docker-compose.fnos.yml up -d
```

数据在 `./data`，不会随镜像更新丢失。升级前建议停止容器并复制整个 `data/` 目录。

## 常见问题

| 现象 | 处理 |
| --- | --- |
| `pull access denied` / 无法拉取镜像 | 先确认仓库和 GHCR 包是公开的；私有包需要 `docker login ghcr.io` |
| 3000 端口被占用 | 改 `.env` 的 `APP_PORT`，重启 Compose |
| 手机 WebDAV 测试失败 | 必须 HTTPS；检查域名、证书、反向代理是否保留 `/dav/` |
| 首次转写很慢 | 首次会下载模型；CPU 上 `small` 需要一点时间，之后会复用 `data/models/` |
| 容器启动但页面 503 | 使用镜像方式时不应出现；源码方式请确认 `web` 构建成功 |
| 权限错误 | 确保 `./data` 可写；容器启动时会尝试 chown，必要时 `sudo chown -R 1000:1000 data` |
