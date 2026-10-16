import Testing
@testable import PauseGuardApp

@Suite @MainActor struct EmergencyReleaseSessionTests {
    @Test func correctCodeRequiresFullFiveSecondsAndConfirmationIsSingleUse() {
        var now = ContinuousClock.now
        let session = EmergencyReleaseSession(now: { now })
        session.input = session.challenge
        #expect(session.remainingSeconds == 5)
        #expect(!session.canConfirm)
        #expect(!session.confirm())
        now = now.advanced(by: .milliseconds(4_999))
        #expect(session.remainingSeconds == 1)
        #expect(!session.confirm())
        now = now.advanced(by: .milliseconds(1))
        #expect(session.remainingSeconds == 0)
        #expect(session.canConfirm)
        #expect(session.confirm())
        #expect(!session.canConfirm)
        #expect(!session.confirm())
    }

    @Test func delayedRefreshUsesElapsedTimeAndRejectsWrongOrMalformedInput() {
        var now = ContinuousClock.now
        let session = EmergencyReleaseSession(now: { now })
        now = now.advanced(by: .seconds(17))
        #expect(session.remainingSeconds == 0)
        let wrong = session.challenge == "0000" ? "0001" : "0000"
        for input in ["", wrong, "123", "12345", "１２３４", "١٢٣٤", " " + session.challenge, session.challenge + "\n"] {
            session.input = input
            #expect(!session.canConfirm)
            #expect(!session.confirm())
        }
        session.input = session.challenge
        #expect(session.confirm())
    }

    @Test func cancellationInvalidatesOldAttemptAndReentryStartsNewWaitAndInput() {
        var now = ContinuousClock.now
        let old = EmergencyReleaseSession(now: { now })
        old.input = old.challenge
        now = now.advanced(by: .seconds(5))
        old.cancel()
        #expect(!old.canConfirm)
        #expect(!old.confirm())
        let replacement = EmergencyReleaseSession(now: { now })
        #expect(replacement.input.isEmpty)
        #expect(replacement.challenge.utf8.count == 4)
        #expect(replacement.challenge.utf8.allSatisfy { (48...57).contains($0) })
        replacement.input = replacement.challenge
        #expect(replacement.remainingSeconds == 5)
        #expect(!replacement.confirm())
        now = now.advanced(by: .seconds(5))
        #expect(replacement.confirm())
        #expect(!old.confirm())
    }

    @Test func cancellationDuringWaitCannotBecomeReadyLater() {
        var now = ContinuousClock.now
        let session = EmergencyReleaseSession(now: { now })
        session.input = session.challenge
        session.cancel()
        now = now.advanced(by: .seconds(30))
        #expect(!session.canConfirm)
        #expect(!session.confirm())
    }
}
