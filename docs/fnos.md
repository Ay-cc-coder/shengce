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

下载三个文件（`Caddyfile` 只有启用 HTTPS 时才用得到，但一起下载最省事）：

```bash
curl -fLO https://raw.githubusercontent.com/Ay-cc-coder/shengce/main/docker-compose.fnos.yml
curl -fLO https://raw.githubusercontent.com/Ay-cc-coder/shengce/main/.env.example
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

在 `.env` 设置：

```dotenv
DOMAIN=record.example.com
PUBLIC_URL=https://record.example.com
APP_BIND=127.0.0.1
```

确保域名的 A/AAAA 记录指向 fnOS，且路由器把 80/443 转发到 fnOS，然后：

```bash
docker compose -f docker-compose.fnos.yml --profile tls up -d
```

Caddy 会自动申请证书。手机里填写：

- WebDAV 地址：`https://record.example.com/dav/`
- 账号：`.env` 的 `DAV_USERNAME`
- 密码：`.env` 的 `DAV_PASSWORD`

如果 fnOS 已经用别的反向代理提供 HTTPS，也可以只运行 app，把 3000 端口代理到你的域名；注意不要剥掉 `/dav/` 前缀。

如果 80/443 已经被 fnOS 或其他服务占用，请不要强行占用；改用已有反代，或把 `docker-compose.fnos.yml` 里 Caddy 的端口改成其他值并做好转发。

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
