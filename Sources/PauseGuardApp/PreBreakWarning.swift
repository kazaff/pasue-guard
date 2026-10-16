import AppKit
import SwiftUI
import PauseGuardCore

struct PreBreakWarningView: View {
    let seconds: Int
    let nextBreakMinutes: Int
    let skip: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("即将开始休息", systemImage: "pause.circle.fill").font(.headline)
            Text("\(seconds) 秒后进入休息").font(.title3.monospacedDigit())
            Text("跳过后重新计时，下次休息为 \(nextBreakMinutes) 分钟，最高 60 分钟。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("跳过本次，延长下次休息", action: skip).buttonStyle(.bordered)
        }
        .padding(20).frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.18)))
        .padding(10)
    }
}

private final class WarningPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Only instantiated by the real desktop owner; driven by engine time, never a second timer.
@MainActor final class PreBreakWarningController {
    private var panel: NSPanel?
    func update(_ runtime: RuntimeState, baseDuration: TimeInterval, skip: @escaping () -> Void) {
        guard runtime.phase == .preparing, runtime.isAvailable, let screen = NSScreen.screens.first else {
            dismiss(); return
        }
        var next = runtime
        next.skippedBreakCount = min(6, runtime.skippedBreakCount + 1)
        let content = PreBreakWarningView(seconds: max(1, Int(ceil(runtime.workRemainingSeconds))),
            nextBreakMinutes: Int(ceil(next.pendingBreakDuration(base: baseDuration) / 60)), skip: skip)
        let panel = panel ?? {
            let value = WarningPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            value.isReleasedWhenClosed = false; value.level = .floating
            value.backgroundColor = .clear; value.isOpaque = false; value.hasShadow = false
            value.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = value; return value
        }()
        let host: NSHostingView<PreBreakWarningView>
        if let current = panel.contentView as? NSHostingView<PreBreakWarningView> {
            current.rootView = content; host = current
        } else {
            host = NSHostingView(rootView: content); panel.contentView = host
        }
        let size = host.fittingSize
        let frame = screen.visibleFrame
        panel.setFrame(CGRect(x: frame.maxX - size.width - 12, y: frame.maxY - size.height - 12,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }
    func dismiss() { panel?.orderOut(nil); panel?.close(); panel = nil }
    isolated deinit { dismiss() }
}
