import SwiftUI

struct EmergencyReleaseView: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @StateObject private var session = EmergencyReleaseSession()
    @AccessibilityFocusState private var confirmationFocused: Bool
    @FocusState private var codeFocused: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let remaining = session.remainingSeconds
            VStack(spacing: 16) {
                Text("确认中断本次休息？").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($confirmationFocused)
                Text("解除后所有屏幕恢复使用，保护循环将暂停，需要你手动恢复。")
                    .multilineTextAlignment(.center)
                if remaining > 0 {
                    Text("请先停一停，\(remaining) 秒后可验证解除。")
                        .monospacedDigit()
                } else {
                    Text("输入下方 4 位数字，再确认解除。")
                    Text(session.challenge).font(.title.monospaced()).tracking(6)
                        .textSelection(.disabled)
                        .accessibilityLabel("验证码 " + session.challenge.map(String.init).joined(separator: "，"))
                    TextField("4 位验证码", text: $session.input)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 180)
                        .focused($codeFocused)
                        .accessibilityLabel("输入显示的 4 位验证码")
                        .accessibilityHint("完全一致后可以确认解除。")
                    Button("解除并暂停保护") {
                        // Recheck at action time, even if a stale enabled button fires.
                        if session.confirm() { onConfirm() }
                    }
                    .disabled(!session.canConfirm)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                }
                Button("返回休息") { session.cancel(); onCancel() }
                    .buttonStyle(.bordered).controlSize(.large)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.7)))
            .onChange(of: remaining == 0) { _, ready in
                if ready { codeFocused = true }
            }
        }
        .onAppear { confirmationFocused = true }
        .onDisappear { session.cancel() }
    }
}
