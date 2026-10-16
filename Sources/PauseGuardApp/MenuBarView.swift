import SwiftUI
import AppKit
import PauseGuardCore

public struct MenuBarView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow
    public init(model: DesktopModel) { self.model = model; controller = model.controller }
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("PauseGuard", systemImage: "leaf.fill").font(.headline).foregroundStyle(.mint)
            Text(status).font(.title3.bold())
            Text(remaining).font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
            Text("第 \(controller.runtime.cycleNumber) 个周期 · 休息 \(Int(controller.settings.breakDurationSeconds / 60)) 分钟").font(.caption).foregroundStyle(.secondary)
            Divider()
            if model.preferences.onboardingComplete {
                Button("提前休息", systemImage: "cup.and.saucer") { controller.send(.beginBreak) }
                    .disabled(![.working, .preparing].contains(controller.runtime.phase))
                if controller.runtime.phase == .paused {
                    Button("继续保护", systemImage: "play.fill") { controller.send(.resume) }
                } else if controller.runtime.phase == .stopped {
                    Button("开始保护", systemImage: "play.fill") { model.start() }
                } else {
                    Button("暂停保护", systemImage: "pause.fill") { controller.send(.pause) }.disabled(!model.editingAllowed)
                }
            } else {
                Button("完成首次配置…") { showSettings() }
            }
            Button("打开设置…", systemImage: "slider.horizontal.3") { showSettings() }
            Divider()
            Button("退出 PauseGuard") { if controller.requestQuit() { model.shutdown(); NSApp.terminate(nil) } }.disabled(!model.editingAllowed)
            if let error = controller.lastError ?? model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if model.isDemo { Text("演示 · 时间加速 15 倍 · 独立临时数据").font(.caption2).foregroundStyle(.orange) }
        }.padding(20).frame(width: 285).buttonStyle(.plain)
    }
    private func showSettings() { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }
    private var status: String {
        switch controller.runtime.phase {
        case .working: "专注工作中"
        case .preparing: "即将休息"
        case .breaking: "正在休息"
        case .paused: "保护已暂停"
        default: "准备好照顾自己了吗？"
        }
    }
    private var remaining: String {
        let value = controller.runtime.phase == .breaking ? controller.runtime.breakRemainingSeconds : controller.runtime.workRemainingSeconds
        let seconds = Int(max(0, ceil(value)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
