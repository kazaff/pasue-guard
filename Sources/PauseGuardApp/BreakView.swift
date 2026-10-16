import SwiftUI
import PauseGuardCore

@MainActor final class BreakViewModel: ObservableObject {
    @Published var runtime: RuntimeState
    @Published var image: CGImage?
    @Published var message = "让目光看向远处，放松肩膀，起身活动。"
    @Published var reduceVisualStimulation = false
    init(runtime: RuntimeState) { self.runtime = runtime }
}

struct BreakView: View {
    @ObservedObject var model: BreakViewModel
    let onEvent: (EngineEvent) -> Void
    @State private var confirmingEmergency = false
    private var countdown: String {
        let remaining = model.runtime.breakRemainingSeconds
        let seconds = remaining.isFinite ? Int(ceil(max(0, min(3600, remaining)))) : 0
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                BreakBackdrop(image: model.image, reduceVisualStimulation: model.reduceVisualStimulation)
                ScrollView {
                    BreakInfoPanel(backdrop: BreakPanelBackdrop(image: model.image, sceneSize: geometry.size, reduceVisualStimulation: model.reduceVisualStimulation), countdown: countdown, message: model.message,
                        countdownSize: min(100, max(44, geometry.size.width * 0.12))) {
                        if !model.runtime.cycleSettings.strictMode {
                            Button("结束本次休息") { onEvent(.endBreak) }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                        }
                        // Inline confirmation remains inside the cover's window level.
                        // A standard sheet could end up below another screen's cover.
                        if confirmingEmergency {
                            EmergencyReleaseView(onCancel: { confirmingEmergency = false }, onConfirm: { onEvent(.emergencyRelease) })
                        } else {
                            Button("紧急解除…") { confirmingEmergency = true }
                                .buttonStyle(.bordered).controlSize(.large)
                                .accessibilityHint("打开确认步骤。确认后解除所有覆盖并暂停循环。")
                        }
                    }
                    .padding(.horizontal, max(16, geometry.safeAreaInsets.leading + 16))
                    .padding(.vertical, max(32, geometry.safeAreaInsets.top + 16))
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }.coordinateSpace(name: BreakPanelBackdrop.coordinateSpace)
                .foregroundStyle(.white)
        }
        // No animations, focus traps or keyboard monitors. System shortcuts and
        // VoiceOver keep their normal event path in both strict and relaxed modes.
        .preferredColorScheme(.dark)
    }
}
