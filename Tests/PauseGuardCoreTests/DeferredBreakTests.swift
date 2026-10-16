import Testing
import Foundation
@testable import PauseGuardCore

struct DeferredBreakTests {
    @Test func skipOnlyDuringWarningAndCompoundsUntilFullRest() {
        let settings = UserSettings(workDurationSeconds: 300, breakDurationSeconds: 60, preBreakWarningSeconds: 30)
        var engine = TimerEngine(settings: settings)
        engine.handle(.start, at: 0)
        engine.handle(.skipUpcomingBreak, at: 10)
        #expect(engine.state.cycleNumber == 1)
        engine.handle(.tick(idleSeconds: 0), at: 270)
        engine.handle(.skipUpcomingBreak, at: 270)
        #expect(engine.state.phase == .working)
        #expect(engine.state.workRemainingSeconds == 300)
        #expect(engine.state.skippedBreakCount == 1)
        engine.handle(.tick(idleSeconds: 0), at: 540)
        engine.handle(.skipUpcomingBreak, at: 540)
        #expect(engine.state.skippedBreakCount == 2)
        engine.handle(.beginBreak, at: 540)
        #expect(engine.state.breakRemainingSeconds == 240)
        engine.handle(.tick(idleSeconds: 0), at: 779)
        #expect(engine.state.phase == .breaking)
        engine.handle(.tick(idleSeconds: 0), at: 780)
        #expect(engine.state.skippedBreakCount == 0)
        engine.handle(.beginBreak, at: 780)
        #expect(engine.state.breakRemainingSeconds == 60)
    }
    @Test func repeatedSkipsCapAtOneHourAndEarlyEndKeepsDebt() {
        let settings = UserSettings(workDurationSeconds: 300, breakDurationSeconds: 300, strictMode: false, preBreakWarningSeconds: 30)
        var engine = TimerEngine(settings: settings)
        engine.handle(.start, at: 0)
        for i in 1...12 {
            let now = Double(i * 270)
            engine.handle(.tick(idleSeconds: 0), at: now)
            engine.handle(.skipUpcomingBreak, at: now)
        }
        engine.handle(.beginBreak, at: 3240)
        #expect(engine.state.breakRemainingSeconds == 3600)
        engine.handle(.endBreak, at: 3241)
        engine.handle(.beginBreak, at: 3241)
        #expect(engine.state.breakRemainingSeconds == 3600)
        #expect(engine.state.isValidForRestore)
    }
    @Test func persistencePreservesDebtAndOldJSONDefaultsToNone() throws {
        var engine = TimerEngine(settings: UserSettings(preBreakWarningSeconds: 30))
        engine.handle(.start, at: 0)
        engine.handle(.tick(idleSeconds: 0), at: 2670)
        engine.handle(.skipUpcomingBreak, at: 2670)
        let data = try JSONEncoder().encode(engine.state)
        let restored = try JSONDecoder().decode(RuntimeState.self, from: data)
        #expect(restored.skippedBreakCount == 1)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "deferredBreakCount")
        let old = try JSONDecoder().decode(RuntimeState.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.skippedBreakCount == 0)
    }
    @Test func skipAtExpiryCannotCancelAlreadyStartedBreak() {
        var engine = TimerEngine(settings: UserSettings(workDurationSeconds: 300, preBreakWarningSeconds: 30))
        engine.handle(.start, at: 0)
        engine.handle(.tick(idleSeconds: 0), at: 270)
        engine.handle(.skipUpcomingBreak, at: 300)
        #expect(engine.state.phase == .breaking)
        #expect(engine.state.skippedBreakCount == 0)
    }
}

extension DeferredBreakTests {
    @Test func awayRestMustPayDeferredDuration() {
        var engine = TimerEngine(settings: UserSettings(workDurationSeconds: 300, breakDurationSeconds: 60, preBreakWarningSeconds: 30))
        engine.handle(.start, at: 0)
        engine.handle(.tick(idleSeconds: 0), at: 270)
        engine.handle(.skipUpcomingBreak, at: 270)
        engine.handle(.availabilityChanged(sleeping: true, locked: false), at: 280)
        engine.handle(.availabilityChanged(sleeping: false, locked: false), at: 340)
        #expect(engine.state.skippedBreakCount == 1)
        engine.handle(.availabilityChanged(sleeping: true, locked: false), at: 340)
        engine.handle(.availabilityChanged(sleeping: false, locked: false), at: 460)
        #expect(engine.state.skippedBreakCount == 0)
        #expect(engine.state.workRemainingSeconds == 300)
    }
}

extension DeferredBreakTests {
    @Test func sparseTickSubtractsOverrunFromDoubledBreak() {
        var engine = TimerEngine(settings: UserSettings(workDurationSeconds: 300, breakDurationSeconds: 60, preBreakWarningSeconds: 30))
        engine.handle(.start, at: 0)
        engine.handle(.tick(idleSeconds: 0), at: 270)
        engine.handle(.skipUpcomingBreak, at: 270)
        engine.handle(.tick(idleSeconds: 0), at: 600)
        #expect(engine.state.phase == .breaking)
        #expect(engine.state.breakRemainingSeconds == 90)
    }
}
