import Foundation
import Combine

/// One attempt, owned by one inline confirmation view.
@MainActor final class EmergencyReleaseSession: ObservableObject {
    let challenge: String
    @Published var input = ""
    private let now: () -> ContinuousClock.Instant
    private let startedAt: ContinuousClock.Instant
    private var active = true

    init(now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.now = now
        startedAt = now()
        challenge = String(format: "%04d", Int.random(in: 0...9999))
    }

    private var elapsed: Duration { startedAt.duration(to: now()) }
    var remainingSeconds: Int {
        let remaining = Duration.seconds(5) - elapsed
        guard remaining > .zero else { return 0 }
        return min(5, Int(remaining.components.seconds) + (remaining.components.attoseconds > 0 ? 1 : 0))
    }
    var canConfirm: Bool {
        active && elapsed >= .seconds(5) && input == challenge
    }
    func confirm() -> Bool {
        guard canConfirm else { return false }
        active = false
        return true
    }
    func cancel() { active = false }
}
