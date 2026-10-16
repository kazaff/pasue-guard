import Foundation
import Testing
@testable import PauseGuardCore

struct TimerEngineTests {
    // Catch missing transitions at the exact default work and break boundaries.
    @Test func testDefaultCycle() {
        var engine = TimerEngine(settings: UserSettings())
        engine.handle(.start, at: 0)
        engine.handle(.tick(idleSeconds: 0), at: 2699)
        #expect(engine.state.phase == .working)
        #expect(engine.state.workRemainingSeconds == 1)
        engine.handle(.tick(idleSeconds: 0), at: 2700)
        #expect(engine.state.phase == .breaking)
        engine.handle(.tick(idleSeconds: 0), at: 3000)
        #expect(engine.state.phase == .working)
        #expect(engine.state.workRemainingSeconds == 2700)
        #expect(engine.state.cycleNumber == 2)
    }

    @Test func testNonStrictEndBreak() {
        var engine = TimerEngine(settings: UserSettings(strictMode: false))
        engine.handle(.start, at: 0)
        engine.handle(.beginBreak, at: 100)
        engine.handle(.endBreak, at: 101)
        #expect(engine.state.phase == .working)
        #expect(engine.state.cycleNumber == 2)
        #expect(engine.state.workRemainingSeconds == 2700)
    }

    @Test func testStrictRejectsEndBreak() {
        var engine = TimerEngine(settings: UserSettings())
        engine.handle(.start, at: 0)
        engine.handle(.beginBreak, at: 100)
        engine.handle(.endBreak, at: 101)
        #expect(engine.state.phase == .breaking)
        #expect(engine.state.breakRemainingSeconds == 299)
    }

    @Test func testEmergencyPauses() {
        var engine = TimerEngine(settings: UserSettings())
        engine.handle(.start, at: 0)
        engine.handle(.beginBreak, at: 100)
        engine.handle(.emergencyRelease, at: 110)
        engine.handle(.tick(idleSeconds: 0), at: 1000)
        #expect(engine.state.phase == .paused)
        #expect(engine.state.lastTransitionReason == .emergencyRelease)
        #expect(engine.state.breakRemainingSeconds == 290)
    }

    // Catch double counting nested sleep/lock intervals or premature work on wake.
    @Test func testOverlappingSleepAndLock() {
        var engine = TimerEngine(settings: UserSettings())
        engine.handle(.start, at: 0)
        engine.handle(.availabilityChanged(sleeping: true, locked: false), at: 100)
        engine.handle(.availabilityChanged(sleeping: true, locked: true), at: 200)
        engine.handle(.availabilityChanged(sleeping: false, locked: true), at: 300)
        #expect(engine.state.workRemainingSeconds == 2600)
        #expect(engine.state.awayElapsedSeconds == 200)
        engine.handle(.availabilityChanged(sleeping: false, locked: false), at: 400)
        #expect(engine.state.workRemainingSeconds == 2700)
        #expect(engine.state.cycleNumber == 2)
        #expect(engine.state.lastTransitionReason == .awayRestCompleted)
    }

    @Test func testAwayResetsWorkOnlyAfterFullBreak() {
        for (away, expectedWork, expectedCycle) in [(299.0, 2600.0, 1), (300.0, 2700.0, 2)] {
            var engine = TimerEngine(settings: UserSettings())
            engine.handle(.start, at: 0)
            engine.handle(.availabilityChanged(sleeping: true, locked: false), at: 100)
            engine.handle(.availabilityChanged(sleeping: false, locked: false), at: 100 + away)
            #expect(engine.state.workRemainingSeconds == expectedWork)
            #expect(engine.state.cycleNumber == expectedCycle)
        }
    }

    @Test func testBreakExpiresWhileUnavailable() {
        var engine = TimerEngine(settings: UserSettings())
        engine.handle(.start, at: 0)
        engine.handle(.beginBreak, at: 100)
        engine.handle(.availabilityChanged(sleeping: true, locked: false), at: 200)
        engine.handle(.tick(idleSeconds: 0), at: 10000)
        #expect(engine.state.phase == .breaking)
        #expect(engine.state.breakRemainingSeconds == 0)
        #expect(engine.state.cycleNumber == 1)
        engine.handle(.availabilityChanged(sleeping: false, locked: false), at: 11000)
        #expect(engine.state.phase == .working)
        #expect(engine.state.workRemainingSeconds == 2700)
        #expect(engine.state.cycleNumber == 2)
    }

    @Test func testRepeatedAvailabilityEvents() {
        var engine = TimerEngine(settings: UserSettings())
        engine.handle(.start, at: 0)
        engine.handle(.availabilityChanged(sleeping: false, locked: false), at: 100)
        engine.handle(.availabilityChanged(sleeping: true, locked: true), at: 200)
        engine.handle(.availabilityChanged(sleeping: true, locked: true), at: 350)
        engine.handle(.availabilityChanged(sleeping: false, locked: false), at: 500)
        engine.handle(.availabilityChanged(sleeping: false, locked: false), at: 500)
        #expect(engine.state.cycleNumber == 2)
        #expect(engine.state.workRemainingSeconds == 2700)
        #expect(engine.state.awayStartedAt == nil)
    }

    // Catch charging idle time beyond 60 seconds, including a sparse tick.
    @Test func testActiveModeIdleThreshold() {
        var engine = TimerEngine(settings: UserSettings(timerMode: .active))
        engine.handle(.start, at: 0)
        engine.handle(.tick(idleSeconds: 59), at: 59)
        #expect(engine.state.workRemainingSeconds == 2641)
        engine.handle(.tick(idleSeconds: 60), at: 60)
        #expect(engine.state.workRemainingSeconds == 2640)
        engine.handle(.tick(idleSeconds: 61), at: 61)
        #expect(engine.state.workRemainingSeconds == 2640)
        engine.handle(.tick(idleSeconds: 120), at: 120)
        #expect(engine.state.workRemainingSeconds == 2640)
        engine.handle(.tick(idleSeconds: 0), at: 130)
        #expect(engine.state.workRemainingSeconds == 2630)
    }

    @Test func testSettingsApplyNextCycle() {
        var engine = TimerEngine(settings: UserSettings())
        engine.handle(.start, at: 0)
        engine.handle(.updateSettings(UserSettings(workDurationSeconds: 600, breakDurationSeconds: 60, strictMode: false)), at: 100)
        #expect(engine.state.workRemainingSeconds == 2600)
        #expect(engine.state.cycleSettings.workDurationSeconds == 2700)
        engine.handle(.beginBreak, at: 200)
        #expect(engine.state.breakRemainingSeconds == 60)
        #expect(engine.state.cycleSettings.strictMode == false)
        engine.handle(.endBreak, at: 201)
        #expect(engine.state.phase == .working)
        #expect(engine.state.workRemainingSeconds == 600)
        engine.handle(.beginBreak, at: 202)
        engine.handle(.updateSettings(UserSettings(workDurationSeconds: 900, breakDurationSeconds: 120, strictMode: true)), at: 203)
        #expect(engine.state.breakRemainingSeconds == 59)
        #expect(engine.state.cycleSettings.strictMode == false)
        engine.handle(.endBreak, at: 204)
        #expect(engine.state.phase == .working)
        #expect(engine.state.workRemainingSeconds == 900)
        engine.handle(.beginBreak, at: 205)
        #expect(engine.state.breakRemainingSeconds == 120)
        engine.handle(.endBreak, at: 206)
        #expect(engine.state.phase == .breaking)
    }

    @Test func testWarningIsIncludedInWorkDuration() {
        var engine = TimerEngine(settings: UserSettings(preBreakWarningSeconds: 30))
        engine.handle(.start, at: 0)
        engine.handle(.tick(idleSeconds: 0), at: 2670)
        #expect(engine.state.phase == .preparing)
        #expect(engine.state.workRemainingSeconds == 30)
        engine.handle(.tick(idleSeconds: 0), at: 2700)
        #expect(engine.state.phase == .breaking)
    }

    @Test func testPauseResumePreservesRemainingWork() {
        var engine = TimerEngine(settings: UserSettings())
        engine.handle(.start, at: 0)
        engine.handle(.pause, at: 100)
        #expect(engine.state.lastTransitionReason == .userPaused)
        engine.handle(.resume, at: 500)
        engine.handle(.tick(idleSeconds: 0), at: 510)
        #expect(engine.state.workRemainingSeconds == 2590)
        engine.handle(.stop, at: 520)
        engine.handle(.tick(idleSeconds: 0), at: 10000)
        #expect(engine.state.phase == .stopped)
    }

    @Test func testSettingsBoundsProtectTimer() {
        var settings = UserSettings(workDurationSeconds: -1, breakDurationSeconds: 10000, preBreakWarningSeconds: 100)
        var engine = TimerEngine(settings: settings)
        engine.handle(.start, at: 0)
        #expect(engine.state.workRemainingSeconds == 300)
        #expect(engine.state.breakRemainingSeconds == 3600)
        #expect(engine.state.cycleSettings.preBreakWarningSeconds == 60)
        settings.workDurationSeconds = .nan
        settings.breakDurationSeconds = -.infinity
        engine.handle(.stop, at: 1)
        engine.handle(.updateSettings(settings), at: 1)
        engine.handle(.start, at: 1)
        #expect(engine.state.workRemainingSeconds == 2700)
        #expect(engine.state.breakRemainingSeconds == 300)
    }

    @Test func testBackwardAndNonfiniteClockEventsAreIgnored() {
        var engine = TimerEngine(settings: UserSettings())
        engine.handle(.start, at: 100)
        engine.handle(.tick(idleSeconds: 0), at: 200)
        engine.handle(.tick(idleSeconds: 0), at: 150)
        engine.handle(.tick(idleSeconds: 0), at: .nan)
        engine.handle(.tick(idleSeconds: 0), at: 210)
        #expect(engine.state.workRemainingSeconds == 2590)
    }

    @Test func testLateTickPreservesElapsedBreakTime() {
        var engine = TimerEngine(settings: UserSettings())
        engine.handle(.start, at: 0)
        engine.handle(.tick(idleSeconds: 0), at: 2800)
        #expect(engine.state.phase == .breaking)
        #expect(engine.state.breakRemainingSeconds == 200)
    }

    // Catch forgetting real break time after active work expires inside a sparse tick.
    @Test func testActiveWorkExpiryCountsIdleTailAsBreak() {
        var engine = TimerEngine(settings: UserSettings(workDurationSeconds: 300, timerMode: .active))
        engine.handle(.start, at: 0)
        engine.handle(.tick(idleSeconds: 0), at: 290)
        engine.handle(.tick(idleSeconds: 110), at: 400)
        #expect(engine.state.phase == .breaking)
        #expect(engine.state.breakRemainingSeconds == 200)
    }

    @Test func testLongSleepStartsOnlyOneFreshCycleOnReturn() {
        var engine = TimerEngine(settings: UserSettings())
        engine.handle(.start, at: 0)
        engine.handle(.availabilityChanged(sleeping: true, locked: true), at: 100)
        engine.handle(.tick(idleSeconds: 0), at: 100000)
        #expect(engine.state.workRemainingSeconds == 2600)
        #expect(engine.state.cycleNumber == 1)
        engine.handle(.availabilityChanged(sleeping: false, locked: false), at: 200000)
        #expect(engine.state.workRemainingSeconds == 2700)
        #expect(engine.state.cycleNumber == 2)
    }

    @Test func testPauseDuringStrictBreakCannotReleaseIt() {
        var engine = TimerEngine(settings: UserSettings())
        engine.handle(.start, at: 0)
        engine.handle(.beginBreak, at: 1)
        engine.handle(.pause, at: 2)
        #expect(engine.state.phase == .breaking)
        #expect(engine.state.breakRemainingSeconds == 299)
    }

    @Test func testConfigurationAndRuntimeRoundTrip() throws {
        var engine = TimerEngine(settings: UserSettings(workDurationSeconds: 20000, breakDurationSeconds: 1, preBreakWarningSeconds: -1))
        engine.handle(.start, at: 0)
        #expect(engine.state.workRemainingSeconds == 10800)
        #expect(engine.state.breakRemainingSeconds == 60)
        #expect(engine.state.cycleSettings.preBreakWarningSeconds == 0)
        engine.handle(.availabilityChanged(sleeping: true, locked: false), at: 10)
        let encoded = try JSONEncoder().encode(engine.state)
        let decoded = try JSONDecoder().decode(RuntimeState.self, from: encoded)
        #expect(decoded == engine.state)
        #expect(decoded.awayStartedAt == 10)
        #expect(decoded.sleeping)
    }
}
