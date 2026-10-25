# Security

## 凭据

- WebDAV 密码只保存在本机，不写入日志。
- App 侧优先使用 Keychain；RootHide 环境没有可用 keychain access group 时，回退到本机 NSUserDefaults。
- 开始监控后，daemon 还会把密码保存到受保护的本地配置文件。
- 提交 issue / 截图 / 日志前，请先移除服务器地址、账号、密码、文件路径等隐私信息。

## 报告问题

这是一个越狱工具，会以 root 运行 launchd daemon。若发现权限、凭据泄露、路径穿越或任意文件上传问题，请优先通过私密渠道联系维护者，不要直接公开可复现的敏感细节。

## 使用边界

只在你拥有或获授权的设备、文件夹和 WebDAV 服务器上使用。不要用本工具上传未经授权的数据。
