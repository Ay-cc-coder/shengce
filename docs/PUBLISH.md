# 发布到 GitHub

当前仓库：<https://github.com/Ay-cc-coder/audio-watch>  
当前 Release：<https://github.com/Ay-cc-coder/audio-watch/releases/tag/v1.0.6>

本文按“首次发布”到“后续发版”说明。默认仓库名 `audio-watch`，许可证 MIT；可以按需要修改。

## 1. 创建仓库

1. 登录 GitHub，点右上角 **+ → New repository**。
2. Repository name：`audio-watch`（或 `roothide-audiowatch`）。
3. 选择 **Public**（如果要公开）或 Private。
4. 不要勾选 “Add a README / .gitignore / license”，本地已经有这些文件。
5. 创建后复制仓库地址，例如：
   - HTTPS：`https://github.com/<你的用户名>/audio-watch.git`
   - SSH：`git@github.com:<你的用户名>/audio-watch.git`

建议仓库描述：

> RootHide iOS app + launchd daemon: silently upload recordings from a chosen folder to an HTTPS WebDAV directory, with persistent queue and original filenames.

建议 Topics：

`ios` `jailbreak` `roothide` `webdav` `objective-c` `launchd` `dopamine`

## 2. 配置 Git 身份

在本机执行一次：

```bash
git config --global user.name "你的名字"
git config --global user.email "你的 GitHub 邮箱"
```

如果只想给这个仓库设置：

```bash
cd "/Users/liseng/codex/ios插件开发/录音文件监控"
git config user.name "你的名字"
git config user.email "你的 GitHub 邮箱"
```

## 3. 初始化并提交

本目录已经执行过 `git init -b main` 和 `git add .`，文件已暂存。直接配置作者并提交即可：

```bash
cd "/Users/liseng/codex/ios插件开发/录音文件监控"
git config user.name "你的名字"
git config user.email "你的 GitHub 邮箱"
git status
git commit -m "release: 录音监控 1.0.6"
```

如果从一份全新拷贝开始，再补上：

```bash
git init -b main
git add .
```

提交前检查：

```bash
git diff --cached --stat
git diff --cached | grep -iE 'password|secret|token' || true
```

不要把真实的 WebDAV 密码、账号、设备 IP 或私人录音提交进仓库。

## 4. 连接远程并推送

```bash
git remote add origin https://github.com/<你的用户名>/audio-watch.git
git push -u origin main
```

如果使用 SSH：

```bash
git remote add origin git@github.com:<你的用户名>/audio-watch.git
git push -u origin main
```

HTTPS 推送需要 GitHub Personal Access Token（不要用账号密码）。也可以安装 GitHub Desktop，用它完成 Add local repository → Publish。

## 5. 创建 Release（推荐）

仓库里已经包含 `.github/workflows/release.yml`。推送 `v*` 标签后会自动创建 Release，并把 `packages/*.deb` 作为附件：

```bash
git tag v1.0.6
git push origin v1.0.6
```

然后到 **Actions** 查看 Release workflow；成功后到 **Releases** 下载 `.deb`。

如果不想用 Actions，也可以在 GitHub 页面：

**Releases → Draft a new release → 选择/创建 tag `v1.0.6` → 上传 `packages/com.liseng.audiowatch_1.0.6_iphoneos-arm64e.deb` → Publish release**。

## 6. 后续更新版本

1. 修改 `control` 和 `Resources/Info.plist` 的版本号。
2. `make clean && make -j1 FINALPACKAGE=1 && make package FINALPACKAGE=1`。
3. 更新 `README.md` 的下载链接和 SHA-256。
4. 更新 `CHANGELOG.md`。
5. 提交：
   ```bash
   git add .
   git commit -m "release: 1.0.7"
   git tag v1.0.7
   git push origin main --tags
   ```

## 7. 可选增强

- 在仓库 About 里勾选 **Releases**、**Packages**。
- 开启 **Discussions** 收集反馈。
- 添加 `CONTRIBUTING.md`、Issue 模板。
- 发布前在 Sileo 源里添加仓库地址，方便用户直接安装。
- 不要提交 `.theos/`、`.modulecache/`、`*.ips`、真实日志或凭据文件；`.gitignore` 已覆盖常见构建产物。

## 8. 安全检查

```bash
# 确认没有构建缓存被提交
git ls-files | grep -E '^\.theos/|^\.modulecache/' || true

# 检查包内文件
dpkg-deb -c packages/*.deb | head

# 验证签名/架构
file packages/*.deb
```

截图中的 `trycloudflare.com` / `awtest` 是测试环境，不是真实账号；如果不想公开测试截图，可以删除 `docs/screenshots/01-idle.png`、`02-monitoring.png`、`03-dark.png`、`04-waiting-network.png` 或替换成自己的截图。
