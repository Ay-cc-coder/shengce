# 架构

## 为什么 App 不直接连 WebDAV

在这台 RootHide / Dopamine 设备上，安装在 `/Applications` 的 App 进程出站连接会返回 `EHOSTUNREACH`（即使是局域网地址），只有 loopback 可用；root 守护进程可以正常访问网络。因此：

- **App** 只负责界面、文件夹选择、状态展示。
- **Daemon** 负责 WebDAV 测试、上传、重试、监控。
- 两者通过 `127.0.0.1:47821` 的本地 HTTP API 通信，使用固定 token 头。
- App 不再直接使用 `NSURLSession` 访问外网，避免不同 RootHide 路径/网络视图造成行为差异。

## 进程

```text
AudioWatch.app (mobile)
  │  loopback HTTP + X-AudioWatch-Token
  ▼
AudioWatchDaemon (root, launchd KeepAlive)
  │  HTTPS WebDAV
  ▼
反向代理后的 WebDAV 目录
```

## 守护进程

- `AWDirectoryWatcher`：递归枚举目录，为每个子目录建立 `DISPATCH_SOURCE_TYPE_VNODE`；事件到来后 0.45s 合并，再扫描。空闲时不产生扫描/轮询。
- `AWDaemon`：配置加载、初始扫描、稳定性检查（1.8s，变化则重排）、串行上传、队列持久化、状态发布、API。
- `AWUploader`：WebDAV PUT；必要时逐级 MKCOL；Basic/Digest；HTTPS；从文件流式上传；错误分类。
- `AWWebDAVClient`：连接测试。`PROPFIND Depth: 0` → 账号验证 → PUT 探针 → DELETE 探针。
- `SystemConfiguration`：对 WebDAV 主机做被动可达性监测；离线时不安排重试定时器，恢复时继续。
- 队列/账本：`/var/mobile/Library/Preferences/com.liseng.audiowatch/state/queue.json`（守护进程视图），记录待传、已传指纹、历史和最后上传。
- 配置/密码：同一前缀下 `config/config.json` 与 `config/secret`，`0600`；密码不写日志。
- App 侧密码优先写入 Keychain；RootHide 系统 App 没有可用 keychain access group 时，回退到本机 NSUserDefaults，以便下次打开自动使用。

## 本地 API

所有请求要求 `X-AudioWatch-Token: aw-7f3c9a1d2e5b4c60`。

| 方法 | 路径 | 作用 |
| --- | --- | --- |
| GET | `/v1/status` | 返回 `status` 与脱敏的 `config` |
| GET | `/v1/health` | 进程存活 |
| POST | `/v1/test` | 用 daemon 的网络执行 WebDAV 验证；密码可省略以使用已存密码 |
| POST | `/v1/config` | 保存并启动/停止完整配置；支持 `useStoredPassword` |
| POST | `/v1/enable` | 用现有已验证配置开始 |
| POST | `/v1/disable` | 停止监控，保留队列 |
| POST | `/v1/scan` | 请求立即扫描 |

`/v1/config` 会校验 test fingerprint；daemon 只接受测试通过的配置。App 在测试成功后计算 fingerprint；使用已存密码时由 daemon 保留原 fingerprint。

## 上传与队列

- 初始扫描发现的文件按发现时间排序，先于后续新文件上传。
- 文件写入稳定（大小/mtime/纳秒 mtime 连续不变）才入队。
- 上传成功：写入账本（path + size + mtime），重启后不会重复上传未变化的文件。
- 上传期间文件变化：成功也不记账，重新做稳定性检查并重传。
- 网络错误：条目标记 `waiting_network`，状态进入等待；可达性恢复后清零退避并继续。
- 404/409/5xx：404 视为反代暂时不可达，退避重试；409 视为目录问题；507 空间不足；401/403 需要处理账号。
- 永久失败不会无限重试；用户重新测试并开始时，daemon 会把 failed 条目重置为等待。
- 本地文件不会被删除。

## RootHide 路径注意

- App 与守护进程对 `/var/mobile` 的视图不同；daemon 实际写入 rootfs 的 `/rootfs/var/mobile`，因此共享数据不作为两进程的通信方式，通信全部走 loopback。
- 守护进程不链接 `libroothide`，避免安装时被 RootHide 补丁改写后签名失效；本实现不需要 `jbroot()`。
- LaunchDaemon 的 `ProgramArguments` 使用 `/usr/local/libexec/AudioWatchDaemon`；安装后由 launchd 解析到 `.jbroot`。

## 构建

```bash
cd ios
make clean
make -j1 FINALPACKAGE=1
make package FINALPACKAGE=1
```

使用 RootHide Theos（`THEOS=~/theos`）。`-j1` 是刻意选择：Theos 的递归 make 在并行模式下可能死锁。产物在 `ios/packages/`。
