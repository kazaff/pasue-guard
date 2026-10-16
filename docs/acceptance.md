# MVP 验收状态

基线：[PRD](../PRD.md) AC-01～AC-14 与[批准设计](superpowers/specs/2026-10-16-pauseguard-mvp-design.md)。自动化结果见[验证记录](verification.md)。**尚未完成完整 MVP 实机验收**；“自动通过”仅指模型、真实本地存储或注入的系统/窗口后端，不代表真实桌面行为通过。

| 验收项 | 自动化证据（通过） | 实机结果 |
|---|---|---|
| AC-01 工作到期进入休息 | TimerEngineTests；DeliveryIntegrationTests 的持久设置→新协调器→完整循环 | 待验证真实菜单、倒计时及覆盖 |
| AC-02 多屏覆盖 | DisplayTopologyTests、BreakWindowControllerTests：新增/移除显示器、布局与释放 | 待验证多屏、Retina、热插拔和主屏切换 |
| AC-03 严格模式不能普通跳过 | 核心拒绝 endBreak；协调器拒绝休息中 stop/pause/quit；PresentationPolicyTests | 待验证 Cmd-Tab、普通关闭、Space、全屏和 Mission Control |
| AC-04 休息结束恢复桌面 | 核心完整循环与覆盖控制器释放测试 | 待验证真实窗口消失及键盘焦点恢复 |
| AC-05 后台编译继续 | 实现仅管理自身窗口；此项无真实任务运行证据 | 待验证覆盖期间持续编译、下载或网络任务 |
| AC-06 多图合成 | AssetLibraryTests、RenderingTests：导入副本、缩略图、五模板像素合成 | 先前已目视检查合成预览；设置导入及真实屏幕展示待验证；HEIC 实文件待验证 |
| AC-07 随机变化 | 选图反重复与模板组合测试 | 待验证连续多个真实周期 |
| AC-08 损坏/删除图片降级 | 图片边界/删除测试；DeliveryIntegrationTests：真实坏库 I/O→默认覆盖→仍处于休息 | 待验证 GUI 默认背景与可读性 |
| AC-09 睡眠计入休息 | TimerEngineTests、RecoveryAvailabilityTests：未满/到期、返回才开工作周期 | 待验证真实睡眠/唤醒通知与窗口恢复 |
| AC-10 UI 异常退出恢复 | RecoveryTests、AgentRecoveryTests；DeliveryIntegrationTests：保存 break 快照→新协调器剩余 90 秒→到期 | 待验证真实进程崩溃、守护拉起、限速与桌面释放 |
| AC-11 改墙上时钟不缩短休息 | 单调时钟与同启动/跨重启恢复测试 | 待验证真实系统时钟变更 |
| AC-12 紧急解除恢复交互 | 覆盖先释放再发事件；真实会话文件存 paused/breaking；新协调器仍暂停 | 待验证真实确认按钮、所有屏幕释放及输入恢复 |
| AC-13 锁屏及睡眠并集 | 核心并集测试、事件归约与恢复测试；无重复计时 | 待验证真实锁屏/解锁与睡眠重叠 |
| AC-14 非严格结束本次休息 | 核心 endBreak、覆盖先释放回调与策略测试 | 待验证真实按钮、多屏释放并开始新工作周期 |

## 人工矩阵与阻塞

此前控制器执行 `open -n dist/PauseGuard.app --args --demo` 返回 0，并用进程列表确认演示进程。随后原生 CUA `getApp` 等待 3340 秒后报 `-10005 timeoutReached`，没有取得辅助功能树或截图。只结束了本轮演示 PID 78753；没有安装登录项。成功启动只证明进程能启动，**不是 GUI 通过**。本轮未重试失效 UI 服务，未使用替代屏幕捕获。

以下均待人工执行并记录机器、时间、实际结果：

- 首次配置、菜单栏和五栏设置、键盘导航、缩略图/图集/文案、减少动画及透明度、VoiceOver 标签与焦点。
- 单屏、多屏、Retina、不同分辨率、热插拔、主屏切换；普通桌面、全屏应用、Space 和 Mission Control。
- 严格/非严格休息、正常结束、紧急解除确认、系统安全快捷键、异常窗口创建失败后的可操作错误。
- 睡眠/唤醒、锁屏/解锁及重叠，后台编译/下载持续运行，真实崩溃和登录 Agent 恢复、正常退出不重开、注销与重启。
- 实际 HEIC 图片；macOS 14 及其他版本、Intel；Developer ID 签名、公证及首次安装体验。

没有将任何上述未执行场景标为人工通过。单位测试的注入窗口不创建真实覆盖，Agent 测试的 launchctl 为替身；它们不能关闭本表的系统验收项。
