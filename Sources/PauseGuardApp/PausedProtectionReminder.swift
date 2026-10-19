import AppKit
import SwiftUI
import PauseGuardCore
import PauseGuardPlatform

/// Driven by desktop runtime publications, with elapsed time independent of work/break timers.
struct PausedProtectionReminderSchedule {
    private var nextReminderAt: TimeInterval?
    private var visibleUntil: TimeInterval?

    mutating func update(_ runtime: RuntimeState, at now: TimeInterval) -> Bool {
        guard runtime.phase == .paused else {
            self = Self()
            return false
        }
        if nextReminderAt == nil { nextReminderAt = now + 600 }
        guard runtime.isAvailable else {
            visibleUntil = nil
            return false
        }
        if let nextReminderAt, now >= nextReminderAt {
            self.nextReminderAt = now + 600
            visibleUntil = now + 5
        }
        return visibleUntil.map { now < $0 } ?? false
    }
}

struct PausedProtectionReminderView: View {
    let phrase: String
    let resume: () -> Void

    nonisolated static func message(for phrase: String) -> String {
        phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "保护已暂停，请开启保护" : phrase
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("请开启保护", systemImage: "shield.slash").font(.headline)
            ScrollView {
                Text(Self.message(for: phrase))
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 140)
            Button("开启保护", action: resume).buttonStyle(.borderedProminent)
        }
        .padding(20).frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.18)))
        .padding(10)
    }
}

private final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class PausedProtectionReminderController {
    private var schedule = PausedProtectionReminderSchedule()
    private var panel: NSPanel?
    private var autoDismiss: Task<Void, Never>?

    func update(_ runtime: RuntimeState, phrase: String, resume: @escaping () -> Void) {
        guard schedule.update(runtime, at: SystemClock.snapshot().continuousUptime),
              let screen = NSScreen.screens.first else {
            dismiss()
            return
        }
        let content = PausedProtectionReminderView(phrase: phrase, resume: resume)
        let isNew = panel == nil
        let panel = panel ?? {
            let value = ReminderPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            value.isReleasedWhenClosed = false
            value.level = .floating
            value.backgroundColor = .clear
            value.isOpaque = false
            value.hasShadow = false
            value.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = value
            return value
        }()
        let host: NSHostingView<PausedProtectionReminderView>
        if let current = panel.contentView as? NSHostingView<PausedProtectionReminderView> {
            current.rootView = content
            host = current
        } else {
            host = NSHostingView(rootView: content)
            panel.contentView = host
        }
        let size = host.fittingSize
        let frame = screen.visibleFrame
        panel.setFrame(CGRect(x: frame.maxX - size.width - 12, y: frame.maxY - size.height - 12,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        if isNew {
            autoDismiss = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                self?.dismiss()
            }
        }
    }

    func dismiss() {
        autoDismiss?.cancel()
        autoDismiss = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    isolated deinit { dismiss() }
}
