# 发布 iOS 版本

iOS 端位于声册仓库的 `ios/` 目录：

- 仓库：<https://github.com/Ay-cc-coder/shengce>
- iOS Release：<https://github.com/Ay-cc-coder/shengce/releases/tag/ios-v1.0.6>

服务器端与 iOS 端的发布相互独立：服务器镜像由 `.github/workflows/docker.yml` 构建，iOS 安装包由 `.github/workflows/ios-release.yml` 构建。

> 旧的 `audio-watch` 仓库已删除；iOS 的历史提交与源码完整保留在本仓库的 `ios/` 目录。

## 1. 准备版本

1. 修改 `control` 与 `Resources/Info.plist` 里的版本号。
2. 构建安装包（在 `ios/` 目录）：

   ```bash
   cd ios
   make clean
   make -j1 FINALPACKAGE=1
   make package FINALPACKAGE=1
   ```

3. 记录产物与 SHA-256：

   ```bash
   shasum -a 256 packages/*.deb
   ```

4. 更新 `ios/README.md` 的下载文件名和 SHA-256，并更新 `ios/CHANGELOG.md`。

## 2. 提交并推送

在仓库根目录执行：

```bash
git add ios/
git commit -m "release: 录音监控 1.0.7"
git push origin main
```

提交前检查：

```bash
git diff --cached --stat
git diff --cached | grep -iE 'password|secret|token' || true
```

不要把真实的 WebDAV 密码、账号、设备 IP 或私人录音提交进仓库。

## 3. 打标签并发布

```bash
git tag ios-v1.0.7
git push origin ios-v1.0.7
```

推送 `ios-v*` 标签后，[`.github/workflows/ios-release.yml`](../../.github/workflows/ios-release.yml) 会自动创建 Release，并把 `ios/packages/*.deb` 作为附件。

然后到 **Actions → iOS Release** 查看运行结果；成功后到 **Releases** 下载 `.deb`。

如果不想用 Actions，也可以在 GitHub 页面：

**Releases → Draft a new release → 选择/创建 tag `ios-v1.0.7` → 上传 `ios/packages/com.liseng.audiowatch_1.0.7_iphoneos-arm64e.deb` → Publish release**。

> 服务器镜像使用 `v*` 标签，iOS 使用 `ios-v*` 标签，两者不会互相触发。

## 4. 安全检查

```bash
# 确认没有构建缓存被提交
git ls-files ios/ | grep -E '\.theos/|\.modulecache/' || true

# 检查包内文件
dpkg-deb -c ios/packages/*.deb | head

# 验证签名/架构
file ios/packages/*.deb
```

截图中的 `trycloudflare.com` / `awtest` 是测试环境，不是真实账号；如果不想公开测试截图，可以删除 `ios/docs/screenshots/` 下的对应文件或替换成自己的截图。
