# PauseGuard MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付可本地构建运行、可安全恢复、具有个性化背景的 macOS 休息应用。

**Architecture:** 使用独立的 Swift 核心模块处理状态及时间，平台层提供时钟、存储和系统事件。SwiftUI/AppKit 应用消费核心状态；图片模块异步提供背景，Agent 通过受限本地状态判断是否恢复应用。

**Tech Stack:** Swift 6、Swift Package Manager、SwiftUI、AppKit、Core Graphics、Core Image、ImageIO、Foundation、XCTest、LaunchAgent。

**Spec:** `docs/superpowers/specs/2026-10-16-pauseguard-mvp-design.md`

## Global Constraints

- 最低支持 macOS 14，首先验证本机 Apple Silicon 环境。
- 不引入 Rust、Web 容器或第三方产品依赖。
- 所有数据保存在本机，不上传图片、不要求账号。
- 睡眠和锁屏区间按并集处理，不重复计时。
- 背景合成始终异步，不阻塞进入休息。
- 不使用全局键盘屏蔽、内核扩展或更改系统安全设置。
- 开机启动必须经用户主动确认。
- 当前周期使用开始时的配置快照。
- 未执行的场景标记为待验证，不能当作通过。
- 当前目录不是 Git 仓库；在执行开始时初始化本地仓库，按任务记录提交，不创建远程仓库或发布。

## Review Focus

- 睡眠与锁屏事件嵌套、乱序或重复，不能双倍累计休息或提前开始工作：任务 1、3。
- 崩溃发生在状态保存期间，不能读取半个文件或永久遮挡桌面：任务 2、5、7。
- 恶意或损坏的配置、巨大图片及异常方向，必须有界降级：任务 2、4。
- 无启用图集、图片删除与显示器热插拔同时发生，休息仍按时触发：任务 4、5。
- 主进程显式退出、重启风暴与状态损坏，Agent 不得持续拉起或锁住桌面：任务 7。

## 文件与共享接口

`Sources/PauseGuardCore/` 放配置、状态、纯状态机；`Sources/PauseGuardPlatform/` 放存储和 macOS 事件；`Sources/PauseGuardImages/` 放素材与合成；`Sources/PauseGuardApp/` 放界面与协调；`Sources/PauseGuardAgent/` 放恢复入口。每个库有对应 Tests 目录。应用协调器使用主线程隔离；后台图像与存储通过明确快照交互。

### Task 1: 可测试的计时与状态机

**Files:** `Package.swift`, `.gitignore`, `Sources/PauseGuardCore/Settings.swift`, `RuntimeState.swift`, `TimerEngine.swift`, `Tests/PauseGuardCoreTests/TimerEngineTests.swift`。

**Interfaces:**
- `UserSettings: Codable, Equatable, Sendable`：workDurationSeconds=2700、breakDurationSeconds=300、timerMode=.elapsed、strictMode=true、preBreakWarningSeconds=0；工作范围 300...10800 秒，休息范围 60...3600 秒，预告 0...60 秒，空闲阈值 60 秒。
- `RuntimeState: Codable, Equatable, Sendable`：phase、workRemainingSeconds、breakRemainingSeconds、cycleNumber、lastTransitionReason、周期配置快照及离开状态。
- `TimerEngine.init(settings: UserSettings)`、`mutating func handle(_ event: EngineEvent, at uptime: TimeInterval)`、只读 `state: RuntimeState`。
- `EngineEvent`：start、pause、resume、stop、tick(idleSeconds:)、beginBreak、endBreak、emergencyRelease、availabilityChanged(sleeping:locked:)、updateSettings(UserSettings)。

- [ ] 写核心测试：`testDefaultCycle` 在 2700 秒进入休息、300 秒后进入下一周期；`testNonStrictEndBreak` 结束后工作；`testStrictRejectsEndBreak` 保持休息；`testEmergencyPauses` 解除后暂停；先运行 `swift test --filter TimerEngineTests`，确认缺少实现而失败。
- [ ] 实现配置校验、状态及状态机；区分暂停原因，预告包含于工作时长，持续休眠不跨越多个工作周期。
- [ ] 增加 `testOverlappingSleepAndLock`，睡眠锁屏重叠 300 秒只记一次；`testAwayResetsWorkOnlyAfterFullBreak`，299 秒保留工作、300 秒重置；`testBreakExpiresWhileUnavailable`，返回桌面才开启工作。
- [ ] 增加 `testActiveModeIdleThreshold`、`testSettingsApplyNextCycle`、`testRepeatedAvailabilityEvents`；运行 `swift test --filter PauseGuardCoreTests`，全部通过后提交。

### Task 2: 原子持久化与恢复决策

**Files:** `Sources/PauseGuardPlatform/StateStore.swift`, `Clock.swift`, `EventLog.swift`, `Tests/PauseGuardPlatformTests/StateStoreTests.swift`, `RecoveryTests.swift`。

**Interfaces:**
- `ClockSnapshot: Codable, Sendable`：continuousUptime、bootID、wallDate；`SystemClock.snapshot() -> ClockSnapshot` 使用包含睡眠时间的单调时钟。
- `PersistedSession: Codable, Sendable`：schemaVersion、runtime、clock、desiredRunning、lastHeartbeat、recoveryAttempts。
- `StateStore.init(directory: URL)`、`loadSettings() -> UserSettings`、`saveSettings(_:) throws`、`loadSession() -> PersistedSession?`、`saveSession(_:) throws`。
- `RecoveryPolicy.restore(_ session: PersistedSession, now: ClockSnapshot) -> RuntimeState`；`EventLog.append(kind: String, detail: String)`。

- [ ] 写 `testAtomicRoundTrip`、`testCorruptSettingsFallBack`、`testCorruptSessionDoesNotStart`、`testUnsupportedVersionIsPreserved`，运行对应测试确认失败。
- [ ] 实现 Application Support 路径、版本校验、受用户权限保护的目录、原子写入和有限大小日志；错误文件保留，安全默认不自动锁屏。
- [ ] 写 `testSameBootRecoveryUsesContinuousTime`、`testRebootPreservesRemainingBreak`、`testWallClockJumpDoesNotShortenBreak`；实现恢复策略及带版本的恢复元数据。
- [ ] 运行 `swift test --filter PauseGuardPlatformTests`，全部通过后提交。

### Task 3: macOS 生命周期与应用协调

**Files:** `Sources/PauseGuardPlatform/SystemEvents.swift`, `ActivityMonitor.swift`, `Sources/PauseGuardApp/AppController.swift`, `Tests/PauseGuardPlatformTests/SystemEventReducerTests.swift`。

**Interfaces:**
- `AvailabilityReducer.update(_ event: AvailabilityEvent) -> Availability`，Availability 包含 sleeping、locked；重复事件幂等。
- `SystemEvents.start(onAvailability: @escaping (Availability) -> Void)`、`stop()`；`ActivityMonitor.idleSeconds() -> TimeInterval`。
- `@MainActor AppController: ObservableObject`：settings、runtime、lastError；`send(_ event: EngineEvent)`、`updateSettings(_:)`、`shutdown()`。

- [ ] 写重复、嵌套、乱序事件测试，确认缺少实现而失败。
- [ ] 实现 NSWorkspace 睡眠/唤醒、会话活跃/不活跃及锁屏通知适配；活动检测仅读取空闲秒数。事件在主线程汇合，锁屏信息无法确认时按保守状态处理。
- [ ] 协调器每秒推进状态，关键转换立即保存，5 秒保存检查点；退出先持久化停止意图。恢复使用任务 2 接口，不复制恢复算法。
- [ ] 运行事件与核心测试；检查实际通知来源与系统版本限制并记录，然后提交。

### Task 4: 本地图片库与五种背景模板

**Files:** `Sources/PauseGuardImages/AssetLibrary.swift`, `Theme.swift`, `ImageSelector.swift`, `Compositor.swift`, `BackgroundCache.swift`, `Tests/PauseGuardImagesTests/`。

**Interfaces:**
- `ImageAsset: Codable, Sendable`：id、内部文件名、宽高、缩略图名；`BreakTheme: Codable, Sendable`：id、name、enabled、imageIDs、layoutMode。
- `AssetLibrary.importImages(_ urls: [URL]) throws -> [ImageAsset]`、`removeImage(id: UUID) throws`、`saveThemes(_ themes: [BreakTheme]) throws`。
- `ImageSelector.select(themes: [BreakTheme], assets: [ImageAsset], previous: Selection?) -> Selection?`。
- `Compositor.render(selection: Selection, size: CGSize, libraryURL: URL) throws -> CGImage`。
- `BackgroundCache` 保存最多 8 项、总计最多 128 MiB；输出尺寸最长边最多 4096 像素，单张解码先降采样。

- [ ] 用临时本地生成测试图写 `testImportCopiesSource`、`testCorruptFileSkipped`、`testDeleteUpdatesThemes`、`testNoEnabledThemesUsesDefault`，确认失败。
- [ ] 实现 PNG/JPEG/HEIC 导入、方向修正、缩略图和版本化元数据，限制导入文件大小 100 MiB，拒绝无效尺寸；单文件失败不取消整批导入。
- [ ] 写 `testFiveLayoutsRender`、`testSingleImageFallback`、`testSelectionAvoidsImmediateRepeatWhenPossible`、`testOversizedImageIsDownsampled`、`testCacheEvicts`；实现 Hero/Grid/Collage/Cinematic/Minimal、渐变、模糊与色彩调整。
- [ ] 运行 `swift test --filter PauseGuardImagesTests`，检查五模板输出，再提交。

### Task 5: 安全的多显示器覆盖

**Files:** `Sources/PauseGuardApp/BreakWindowController.swift`, `BreakView.swift`, `EmergencyReleaseView.swift`, `Sources/PauseGuardPlatform/DisplayTopology.swift`, `Tests/PauseGuardPlatformTests/DisplayTopologyTests.swift`。

**Interfaces:**
- `DisplayTopology.diff(previous: [DisplayDescriptor], current: [DisplayDescriptor]) -> DisplayChanges`，以稳定显示器标识匹配。
- `@MainActor BreakWindowController.show(runtime: RuntimeState, background: BackgroundProvider, onEvent: @escaping (EngineEvent) -> Void) throws`、`update(runtime:)`、`dismiss()`。
- `BackgroundProvider` 按屏幕尺寸获取已有缓存，没有缓存立即返回默认背景，异步结果只更新仍匹配的休息周期。

- [ ] 写 `testHotPlugAddsOnlyNewDisplay`、`testMainDisplayChangeKeepsCoverage`、`testRemovedDisplayIsReleased`，确认失败。
- [ ] 实现每屏无边框窗口、Space/全屏适配、屏幕变化重建及幂等释放；创建失败释放已有窗口并报告协调器暂停。
- [ ] 实现大字号倒计时、安全区域、文案、减少动画/透明度、VoiceOver；非严格模式结束按钮和两步紧急解除。不得使用阻止系统快捷键的事件拦截。
- [ ] 运行拓扑测试并构建应用；真实覆盖、Space 和紧急解除只在显式人工验收模式下测试，记录未测场景，然后提交。

### Task 6: 菜单栏、首次配置与设置

**Files:** `Sources/PauseGuardApp/PauseGuardApp.swift`, `MenuBarView.swift`, `OnboardingView.swift`, `SettingsView.swift`, `ThemeLibraryView.swift`, `BackgroundSettingsView.swift`, `GeneralSettingsView.swift`。

**Interfaces:** 各界面使用任务 3 的 AppController，不直接修改引擎；图片管理使用任务 4 的 AssetLibrary。默认文案和用户文案统一由设置持久化并随机选择。

- [ ] 将工作/休息范围、预告范围、文案空白处理写入设置测试，确认缺少约束时失败。
- [ ] 实现首次配置后明确启用；菜单显示状态和剩余时间，提供提前休息、工作期间暂停/继续、设置和退出。
- [ ] 实现五栏设置、批量图片导入/删除/缩略图、单图/拼贴/模板、图集创建重命名启停删除、自定义文案及辅助功能偏好。
- [ ] 开机启动开关调用任务 7 的显式安装接口；休息期间禁用会绕过约束的修改。增加显式 `--demo` 开发参数，使用独立临时配置，不放宽正常配置范围。
- [ ] 运行 `swift test` 与 `swift build`，人工检查菜单、首次配置和设置布局，然后提交。

### Task 7: 有限的 Agent 恢复与应用打包

**Files:** `Sources/PauseGuardAgent/main.swift`, `Sources/PauseGuardPlatform/AgentRecoveryPolicy.swift`, `LoginItemManager.swift`, `Tests/PauseGuardPlatformTests/AgentRecoveryTests.swift`, `Scripts/build-app.sh`, `Scripts/install-agent.sh`, `Scripts/uninstall-agent.sh`, `Resources/Info.plist`。

**Interfaces:**
- `AgentRecoveryPolicy.decision(session: PersistedSession?, appRunning: Bool, now: Date) -> AgentDecision`：none、relaunch、stopRetrying。
- `LoginItemManager.setEnabled(_ enabled: Bool, appURL: URL) throws`；仅在用户确认后安装/启用用户级 LaunchAgent，同时支持移除。

- [ ] 写 `testExplicitExitDoesNotRestart`、`testMissingOrCorruptStateDoesNotRestart`、`testThreeFailuresWithinFiveMinutesStopRetrying`、`testLiveProcessDoesNotDuplicate`，确认失败。
- [ ] 实现独立 Agent：定期检查存活状态和用户意图，最多 5 分钟内尝试恢复 3 次；只启动已知的打包应用路径，不从状态文件执行命令。
- [ ] 实现 .app 构建，包含主程序、Agent、Info.plist 及资源；LaunchAgent plist 参数使用结构化编码，安装路径限定当前用户 Library/LaunchAgents。开发测试不实际启用登录项。
- [ ] 运行 Agent 测试，执行 `bash Scripts/build-app.sh`，校验 plist、两个可执行文件与包布局；签名/公证能力如未验证明确记录，然后提交。

### Task 8: 集成验证与可交付说明

**Files:** `README.md`, `docs/acceptance.md`, `docs/verification.md`，必要的集成测试及缺陷修复。

**Interfaces:** 不新增产品接口；验证前述任务与 PRD AC-01...AC-14 的映射。

- [x] 写集成测试：设置往返后启动循环、合成失败仍能进入休息、崩溃快照恢复、紧急解除保存暂停意图；先运行失败用例，再修复集成问题。
- [x] 运行 `swift test`、`swift build -c release` 和打包脚本；必要时限制编译并发，保存结果及实际时间。
- [x] 编写首次启动、构建、素材位置、Agent 安装移除、紧急恢复说明；验收清单逐项标明自动通过、人工通过或待验证。
- [ ] 检查多屏、Space、Mission Control、睡眠/锁屏、VoiceOver、后台任务和崩溃恢复的实际证据，禁止以单元测试代替系统验收。
- [ ] 完成独立代码审查并处理确定缺陷；无新修改则不重复无关测试。最终提交并汇报可运行包路径、测试结果和实际限制，不发布远程制品。

## 自查记录

范围映射：计时与策略对应任务 1；持久化和生命周期对应任务 2、3；图片、模板、图集对应任务 4、6；覆盖与安全恢复对应任务 5、7；菜单及设置对应任务 6；交付及全部验收对应任务 8。接口名与跨任务依赖按上文统一，人工系统验证保留独立结果。

Task 8 实际验证：见 `docs/verification.md`。自动测试、release 包及包检查通过；人工矩阵待验证，独立最终审查由控制器执行，最后两项保持未勾选。
