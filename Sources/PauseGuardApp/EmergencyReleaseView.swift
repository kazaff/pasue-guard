import SwiftUI

struct EmergencyReleaseView: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @AccessibilityFocusState private var confirmationFocused: Bool
    var body: some View {
        VStack(spacing: 16) {
            Text("确认紧急解除？").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                .accessibilityFocused($confirmationFocused)
            Text("所有屏幕将立即解除覆盖，循环会暂停。需要你手动恢复。")
                .multilineTextAlignment(.center)
            Button("确认解除并暂停", action: onConfirm)
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button("返回休息", action: onCancel).buttonStyle(.bordered).controlSize(.large)
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.7)))
        .onAppear { confirmationFocused = true }
    }
}
