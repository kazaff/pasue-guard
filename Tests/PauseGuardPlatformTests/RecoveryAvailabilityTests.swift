import Foundation
import Testing
import PauseGuardCore
@testable import PauseGuardPlatform

struct RecoveryAvailabilityTests {
    @Test func expiredBreakWaitsForCurrentLockedDesktopIncludingReboot() {
        for boot in ["saved", "reboot"] {
            var engine = TimerEngine(settings: UserSettings())
            engine.handle(.start, at: 100)
            engine.handle(.beginBreak, at: 100)
            let saved = PersistedSession(runtime: engine.state, clock: ClockSnapshot(continuousUptime: 100, bootID: "saved", wallDate: Date()), desiredRunning: true)
            let restored = RecoveryPolicy.restore(saved, now: ClockSnapshot(continuousUptime: 500, bootID: boot, wallDate: Date()), currentSettings: UserSettings(workDurationSeconds: 600), availability: Availability(sleeping: false, locked: true))
            #expect(restored.phase == .breaking)
            #expect(restored.locked)
            #expect(restored.breakRemainingSeconds == (boot == "saved" ? 0 : 300))
            #expect(restored.awayStartedAt == 500)
        }
    }
}
