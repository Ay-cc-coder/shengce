# fnOS / NAS 安装

推荐直接使用根目录的 [`docker-compose.yml`](../docker-compose.yml)。它只做三件事：

1. 拉取公开镜像 `ghcr.io/ay-cc-coder/shengce:latest`；
2. 把容器内的 8080 映射到宿主机的 **3000**；
3. 把 `./data` 挂载到容器里保存数据库、录音和模型。

**默认不使用 80/443，也不启动 Caddy。** 80/443 留给 fnOS 自己或你已有的反向代理。

## 一、安装

SSH 到 fnOS，创建一个目录（按你的存储池和 UID 调整）：

```bash
sudo mkdir -p /vol1/1000/docker/shengce
sudo chown -R "$(id -u):$(id -g)" /vol1/1000/docker/shengce
cd /vol1/1000/docker/shengce
```

下载 compose 文件：

```bash
curl -fLO https://raw.githubusercontent.com/Ay-cc-coder/shengce/main/docker-compose.yml
```

编辑 `docker-compose.yml`，至少改这两行：

```yaml
ADMIN_PASSWORD: "你的管理密码"
DAV_PASSWORD: "你的WebDAV密码"
```

启动：

```bash
docker compose pull
docker compose up -d
docker compose ps
```

打开：

```text
http://fnOS的IP:3000
```

首次转写会下载 Whisper 模型到 `./data/models/`，之后复用。

## 二、手机接入：复用 NAS 已有的 443

「录音监控」只接受 HTTPS。WebUI 的 `http://IP:3000` 能打开，但手机 WebDAV 测试会失败。

大部分 NAS 的 80/443 已经被管理页或反向代理占用。**不要启动本项目的 Caddy**，直接把现有 HTTPS 域名转发到 app：

```text
https://record.example.com  →  http://127.0.0.1:3000
```

如果反代跑在宿主机上，建议把 compose 的端口改成只监听本机：

```yaml
ports:
  - "127.0.0.1:3000:8080"
```

如果反代本身是一个容器，`127.0.0.1` 不一定指向宿主机；改用 NAS 的局域网 IP（如 `192.168.5.141:3000`）或两者共用的 Docker 网络地址。

Nginx 示例：

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

要点：

- 保留完整路径，**不要剥掉 `/dav/` 前缀**；
- 大文件上传限制至少 512 MB；
- 建议关闭请求缓冲；
- 设置 `X-Forwarded-Proto: https`；
- 证书用 NAS / 反代现有的证书，不需要再给 Caddy 80/443。

手机里填写 `https://record.example.com/dav/`，账号密码用 compose 里的 `DAV_USERNAME` / `DAV_PASSWORD`。

如果 80/443 被占用又没有反向代理，可选：

- 安装 1Panel / Lucky / Nginx Proxy Manager，用它们现有的 443 和证书；
- 使用 Cloudflare Tunnel 或 Tailscale Serve；
- 不要用自签名证书，iOS 插件不会绕过校验。

## 三、可选：Caddy 占用 80/443

只有确认宿主机 80/443 完全空闲时才使用：

```bash
curl -fLO https://raw.githubusercontent.com/Ay-cc-coder/shengce/main/docker-compose.tls.yml
curl -fLO https://raw.githubusercontent.com/Ay-cc-coder/shengce/main/Caddyfile
# 修改 docker-compose.tls.yml 里的 DOMAIN
docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d
```

- 如果 80/443 已被 fnOS 占用，这一步会报 `port is already allocated`；
- 改 Caddy 的监听端口不能自动签发证书，不要这样做；
- 需要 HTTPS 但没有 80/443 时，用上面的已有反代 / Tunnel 方案。

## 四、可选：源码构建

只有想自己编译镜像时才用。源码构建需要完整仓库，不能只下载一个 YAML：

```bash
git clone https://github.com/Ay-cc-coder/shengce.git
cd shengce
cp .env.example .env
# 修改 .env
docker compose -f docker-compose.build.yml up -d --build
```

源码构建镜像名为 `shengce:local`；后续更新需要重新 `--build`。

## 五、更新与数据

更新预构建镜像：

```bash
cd /vol1/1000/docker/shengce
docker compose pull
docker compose up -d
```

数据都在 `./data`，不会随镜像更新丢失：

```text
data/
├── library/       原始文件
├── shengce.db     SQLite
├── models/        Whisper 模型
└── ...
```

升级前建议停止容器并复制整个 `data/`。

## 常见问题

| 现象 | 处理 |
| --- | --- |
| `pull access denied` | 镜像和仓库都是公开的；确认网络能访问 ghcr.io |
| 3000 被占用 | 改 `docker-compose.yml` 的 `ports`，例如 `"3001:8080"` |
| 手机 WebDAV 测试失败 | 必须 HTTPS；检查域名、证书、反代是否保留 `/dav/` |
| 首次转写很慢 | 首次下载模型；CPU 上 `small` 需要一点时间 |
| 80/443 报 `port is already allocated` | 使用了 `docker-compose.tls.yml`；fnOS 上不要用，改用已有反代 |
| 页面打不开 | `docker compose ps` 看容器是否 Up；`docker compose logs -f` 看日志 |
