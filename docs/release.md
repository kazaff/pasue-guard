# PauseGuard 0.1.0 试用包

## 支持范围

- 仅支持 Apple Silicon（M 系列）Mac，不支持 Intel Mac、Windows 或 iOS。
- 最低系统声明为 macOS 14；自动化验证环境为 macOS 26.5.2 / Apple Silicon。macOS 14、15 及其他机器上的实际桌面效果尚待验证。
- 当前为 ad hoc 本地签名的试用包，没有 Developer ID 签名或 Apple 公证；不能承诺在默认 Gatekeeper 设置下直接打开。

## 压缩与发送

构建并检查：

```sh
bash Scripts/test.sh
bash Scripts/build-app.sh
bash Scripts/check-app.sh
```

在 Finder 中只压缩 `dist/PauseGuard.app`。可将本说明一起发送。不要压缩整个项目、`.build` 或原历史备份。构建过程会保留上一版包到被 Git 忽略的 `.build/release-backups`，不应分发它。

发布包只包含程序、Agent、图标、许可证和签名，不包含构建日志、调试信息、用户配置、会话、照片或视频。登录启动配置在用户主动启用后，按接收者的实际安装目录生成。

## 接收者安装

1. 解压，将 PauseGuard.app 拖入“应用程序”目录后打开；不需要安装 Swift 或开发工具。
2. 当前试用包未经公证。如果系统因开发者无法验证而阻止，且确认文件来自可信来源，可在尝试打开后，前往“系统设置 → 隐私与安全”，找到该应用并选择“仍要打开”。受管理的 Mac 可能不允许此操作。
3. 应用在菜单栏显示图标；首次使用需自行设置并启用保护。开机启动默认关闭，需要在设置中主动开启。
4. 开启开机启动后如需移动应用，先关闭开机启动，移动完成后再开启。
5. 如需卸载，先关闭开机启动并退出，再删除应用。个人设置与导入素材保存在 `~/Library/Application Support/PauseGuard`，不会随着删除应用自动移除。

实际多屏、VoiceOver、系统登录恢复和旧版 macOS 验收仍见 [验收清单](acceptance.md)，不能用自动测试代替这些检查。

## 正式公开发布仍需完成

当前机器没有可用的代码签名身份。公开分发前，需要准备 Apple Developer Program 的 Developer ID Application 证书，对主程序及 Agent 启用 Hardened Runtime 并正式签名，提交 Apple 公证、附加公证票据，然后在另一台 Mac 上验证首次安装体验。正式签名和公证完成前，此包应以试用包说明其限制。

Apple 参考：[安全打开应用](https://support.apple.com/en-au/102445)、[Developer ID 分发](https://developer.apple.com/developer-id/)。

## 2026-10-19 本机发布检查

- 全量 159 项测试通过，发布构建及应用包检查通过。
- 主程序与 Agent 均为 arm64，主程序 Mach-O 最低系统版本为 14.0。
- 逐文件扫描未发现个人主目录路径或个人邮箱；包内文件清单仅包含两个可执行文件、Info.plist、图标、许可证和代码签名。
- 复制到含空格的新目录后，严格签名校验和基于新目录生成登录配置均通过；验证过程未安装登录项。
- `codesign --verify --deep --strict` 通过。`spctl --assess --type execute` 返回 `rejected`，符合当前 ad hoc 未公证试用包的状态；不能据此宣称已通过 Gatekeeper。
