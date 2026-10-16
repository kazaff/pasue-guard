import Foundation
import Testing
import PauseGuardCore
@testable import PauseGuardPlatform

struct RecoveryTests {
    @Test func testExpiredBreakUsesCurrentSettingsForNextWork() {
        let settings = UserSettings(workDurationSeconds: 600, breakDurationSeconds: 120, timerMode: .active, strictMode: false, preBreakWarningSeconds: 30)
        let now = ClockSnapshot(continuousUptime: 2000, bootID: "boot-a", wallDate: Date())
        let restored = RecoveryPolicy.restore(session(), now: now, currentSettings: settings)
        #expect(restored.phase == .working)
        #expect(restored.workRemainingSeconds == 600)
        #expect(restored.breakRemainingSeconds == 120)
        #expect(restored.cycleSettings == settings)
    }
    @Test func testCurrentSettingsDoNotChangeOngoingBreakSnapshot() {
        let settings = UserSettings(workDurationSeconds: 600, breakDurationSeconds: 60, strictMode: false)
        let now = ClockSnapshot(continuousUptime: 1050, bootID: "boot-a", wallDate: Date())
        let restored = RecoveryPolicy.restore(session(), now: now, currentSettings: settings)
        #expect(restored.phase == .breaking)
        #expect(restored.breakRemainingSeconds == 150)
        #expect(restored.cycleSettings.breakDurationSeconds == 300)
        #expect(restored.cycleSettings.strictMode)
    }

    @Test func testMissingPausedPhaseCannotRestoreOrResumeAsWork() {
        var saved = session(phase: .paused)
        saved.runtime.pausedPhase = nil
        let restored = RecoveryPolicy.restore(saved, now: saved.clock)
        #expect(restored.phase == .stopped)
        var engine = TimerEngine(restoring: saved.runtime, settings: UserSettings(), at: 1000)
        engine.handle(.resume, at: 1000)
        #expect(engine.state.phase == .stopped)
    }

    @Test func testSameBootRecoveryUsesContinuousTime() {
        let restored = RecoveryPolicy.restore(session(), now: ClockSnapshot(continuousUptime: 1050, bootID: "boot-a", wallDate: .distantPast))
        #expect(restored.phase == .breaking)
        #expect(restored.breakRemainingSeconds == 150)
    }
    @Test func testRebootPreservesRemainingBreak() {
        let restored = RecoveryPolicy.restore(session(), now: ClockSnapshot(continuousUptime: 10, bootID: "boot-b", wallDate: .distantFuture))
        #expect(restored.phase == .breaking)
        #expect(restored.breakRemainingSeconds == 200)
    }
    @Test func testWallClockJumpDoesNotShortenBreak() {
        for date in [Date.distantPast, .distantFuture] {
            #expect(RecoveryPolicy.restore(session(), now: ClockSnapshot(continuousUptime: 1001, bootID: "boot-a", wallDate: date)).breakRemainingSeconds == 199)
        }
    }
    @Test func testExpiredBreakStartsOneFreshWorkCycle() {
        let restored = RecoveryPolicy.restore(session(), now: ClockSnapshot(continuousUptime: 2000, bootID: "boot-a", wallDate: Date()))
        #expect(restored.phase == .working)
        #expect(restored.workRemainingSeconds == 2700)
        #expect(restored.cycleNumber == 2)
    }
    @Test func testWorkDowntimeDoesNotConsumeWork() {
        var saved = session(phase: .working)
        saved.runtime.workRemainingSeconds = 700
        #expect(RecoveryPolicy.restore(saved, now: ClockSnapshot(continuousUptime: 2000, bootID: "boot-a", wallDate: Date())).workRemainingSeconds == 700)
    }
    @Test func testInvalidAndDisabledRecoveryIsStopped() {
        var saved = session()
        saved.runtime.breakRemainingSeconds = .nan
        #expect(RecoveryPolicy.restore(saved, now: saved.clock).phase == .stopped)
        saved = session()
        saved.desiredRunning = false
        #expect(RecoveryPolicy.restore(saved, now: saved.clock).phase == .stopped)
    }
    @Test func testEngineRestoreContinuesWithoutChargingDowntimeTwice() {
        let restored = RecoveryPolicy.restore(session(), now: ClockSnapshot(continuousUptime: 1050, bootID: "boot-a", wallDate: Date()))
        var engine = TimerEngine(restoring: restored, settings: UserSettings(), at: 1050)
        engine.handle(.tick(idleSeconds: 0), at: 1060)
        #expect(engine.state.breakRemainingSeconds == 140)
    }
    @Test func testMalformedRuntimeNeverRestoresEnforcement() {
        var invalidStates: [RuntimeState] = []
        var runtime = session().runtime
        runtime.workRemainingSeconds = -.infinity
        invalidStates.append(runtime)
        runtime = session().runtime
        runtime.awayElapsedSeconds = -.infinity
        invalidStates.append(runtime)
        runtime = session().runtime
        runtime.cycleSettings.breakDurationSeconds = -1
        invalidStates.append(runtime)
        runtime = session().runtime
        runtime.cycleNumber = Int.max
        invalidStates.append(runtime)
        runtime = session().runtime
        runtime.phase = .paused
        runtime.pausedPhase = .stopped
        invalidStates.append(runtime)
        for runtime in invalidStates {
            var saved = session()
            saved.runtime = runtime
            #expect(RecoveryPolicy.restore(saved, now: saved.clock).phase == .stopped)
        }
    }
    @Test func testRebootClearsStaleAvailabilityAndRebasesEngine() {
        var saved = session()
        saved.runtime.locked = true
        saved.runtime.awayStartedAt = 900
        let now = ClockSnapshot(continuousUptime: 10, bootID: "boot-b", wallDate: Date())
        let state = RecoveryPolicy.restore(saved, now: now)
        #expect(state.isAvailable)
        #expect(state.awayStartedAt == nil)
        var engine = TimerEngine(restoring: state, settings: UserSettings(), at: 10)
        engine.handle(.tick(idleSeconds: 0), at: 20)
        #expect(engine.state.breakRemainingSeconds == 190)
    }
    @Test func testSystemClockHasStableBootAndMonotonicTime() {
        let first = SystemClock.snapshot()
        let second = SystemClock.snapshot()
        #expect(!first.bootID.isEmpty)
        #expect(first.bootID == second.bootID)
        #expect(first.continuousUptime >= 0)
        #expect(second.continuousUptime >= first.continuousUptime)
    }
}
