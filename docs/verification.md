# 本地验证记录

日期：2026-10-16；以下时间均为 **Asia/Taipei（UTC+08:00）**。基线提交 `94fb40b`；本轮包含集成测试、系统结束会话意图修复及交付文档。独立最终代码审查由控制器另行执行，本记录不替代其结果。

## 环境与复现

- macOS 26.5.2（25F84），arm64。
- Apple Swift 6.3.2，swift-driver 1.148.6，Command Line Tools；Swift Testing 1902。
- Package.swift 与 Info.plist 声明 macOS 14；未在 macOS 14、Intel 或其他系统版本运行。
- 仓库：`.`。

在仓库根目录执行：

```sh
bash Scripts/test.sh
bash Scripts/build-app.sh
bash Scripts/check-app.sh
```

`Scripts/test.sh` 执行 `swift test` 并提供 CLT Testing 框架路径及本地模块缓存。`Scripts/build-app.sh` 执行 `swift build -c release`（含本地缓存、disable-sandbox 参数），随后复制两个可执行文件、生成 plist 并 ad hoc 签名。`Scripts/check-app.sh` 校验路径、标识符、参数、plist、执行权限及签名；拒绝演示模式安装/移除的负向检查在副作用前退出。

## 最新完整运行

| 命令 | 开始 | 结束 | 实际结果 |
|---|---|---|---|
| `bash Scripts/test.sh` | 11:19:19 | 11:19:23 | exit 0；报告 111 tests、16 suites，0 失败；其中 1 项 HEIC 编码器用例显式跳过 |
| `bash Scripts/build-app.sh` | 11:19:23 | 11:19:31 | exit 0；release 构建通过，两个程序及三份 plist 打包通过，ad hoc 签名校验通过 |
| `bash Scripts/check-app.sh` | 11:19:31 | 11:19:31 | exit 0；bundle smoke checks passed；demo 安装/脚本选项拒绝检查通过 |

关键输出：

```text
Test testHEICImportWhenEncoderAvailable() skipped:
  "Requires a working local HEIC encoder; opt in with PAUSEGUARD_TEST_HEIC_ENCODER=1"
Test run with 111 tests in 16 suites passed after 0.723 seconds.
Bundle smoke checks passed: ./dist/PauseGuard.app
```

测试总数是测试运行器报告数，包含显式跳过项；不能据此宣称 111 项实际执行，也不能宣称 HEIC 实文件已验证。应用路径为 `dist/PauseGuard.app`，为本机 arm64 输出；本地 ad hoc 签名不等于 Developer ID 签名、公证或其他机器 Gatekeeper 安装通过。

## 集成与 RED/GREEN

新增 `Tests/PauseGuardAppTests/DeliveryIntegrationTests.swift` 四个场景：

1. 真实设置文件往返后，新 AppController 使用配置完成工作→休息→下一工作周期。
2. 损坏图片库路径触发真实后台 I/O 失败；BreakWindowController 仍立即建立默认背景（注入窗口），紧急解除释放后把 paused/breaking 保存到真实 session，新协调器仍暂停。
3. 保存未完成休息快照，再由新协调器计算同启动剩余时间并完成休息。
4. 系统结束会话与普通退出分流：严格休息拒绝普通退出，允许系统退出并释放覆盖，保存恢复意图，后续 cleanup 不覆写；重新打开继续未完成休息。

前三项首次运行已通过，补充跨模块验证，没有虚构产品缺陷或 RED。第四项在修复前运行出现 **4 个实际断言失败**：`desiredRunning` 被写为 false（两次检查）、新协调器成为 stopped、剩余休息仍 300 而非应有的 270。引入 `shutdown(preservingSession:)` 与 `requestTermination(systemSessionEnding:)` 后，针对四项的运行报告 4 tests 通过（0.148 秒）；最后全量结果见上表。

系统结束会话路径保留快照和恢复意图；主动退出清除恢复意图；首次 shutdown 决定结果，重复清理幂等。应用 delegate 使用 quit Apple event 的 `kAEQuitReason`（quit all、shutdown、restart、logout）和 workspace willPowerOff 通知识别系统终止，willTerminate 的最终清理保留未主动停止的状态。**真实注销/重启事件投递与时序未执行验收**。

## GUI 与系统验收限制

先前演示启动命令返回 0、进程存在，仅是启动证据。原生 UI 服务 `getApp` 等待 3340 秒后返回 `-10005 timeoutReached`，未取得 AX 树或截图。控制器只向自己启动的 PID 78753 发送 SIGTERM。此轮未再调用 UI 自动化或屏幕捕获，也没有安装 Agent、调用真实 launchctl、睡眠、锁屏、注销、重启或更改系统时钟。

因此首次配置、菜单、真实覆盖、紧急解除、多屏、Space、Mission Control、VoiceOver、后台任务与 Agent 实际恢复均待人工验证；详见 [AC-01～AC-14 与人工矩阵](acceptance.md)。之前目视检查的合成图片只支持模板预览结论。当前状态是可本地构建的候选包，不能宣称完整 MVP 验收完成。
