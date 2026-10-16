import Foundation
import Testing
import PauseGuardCore
@testable import PauseGuardPlatform

struct DeferredRecoveryTests {
    @Test func stoppedSessionKeepsDebtWithoutRestartingAndCompletedBreakClearsIt() {
        var state = RuntimeState(); state.skippedBreakCount = 3
        let clock = ClockSnapshot(continuousUptime: 100, bootID: "test", wallDate: Date())
        let stopped = PersistedSession(runtime: state, clock: clock, desiredRunning: false)
        let recovered = RecoveryPolicy.restore(stopped, now: clock)
        #expect(recovered.phase == .stopped)
        #expect(recovered.skippedBreakCount == 3)
        state.phase = .breaking; state.breakRemainingSeconds = 10
        let running = PersistedSession(runtime: state, clock: clock, desiredRunning: true)
        var later = clock; later.continuousUptime = 110
        let completed = RecoveryPolicy.restore(running, now: later)
        #expect(completed.phase == .working)
        #expect(completed.skippedBreakCount == 0)
    }
}
