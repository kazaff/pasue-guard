import Testing
import CoreGraphics
@testable import PauseGuardPlatform

struct SystemEventReducerTests {
    @Test func duplicateAndOverlappingEventsDoNotPrematurelyReturn() {
        var reducer = AvailabilityReducer(initial: Availability(sleeping: false, locked: false))
        #expect(reducer.update(.locked).locked)
        #expect(reducer.update(.locked).locked)
        #expect(reducer.update(.sleep).sleeping)
        #expect(reducer.update(.wake).locked)
        #expect(!reducer.update(.unlocked).locked)
    }
    @Test func SessionAndScreenLocksAreIndependent() {
        var reducer = AvailabilityReducer(initial: Availability(sleeping: false, locked: false))
        _ = reducer.update(.sessionInactive)
        _ = reducer.update(.locked)
        #expect(reducer.update(.sessionActive).locked)
        _ = reducer.update(.sessionInactive)
        #expect(reducer.update(.unlocked).locked)
        #expect(!reducer.update(.sessionActive).locked)
        #expect(!reducer.update(.wake).sleeping)
    }
    @Test func unknownInitialStateIsConservative() {
        var reducer = AvailabilityReducer()
        #expect(reducer.availability.locked)
        #expect(reducer.update(.wake).locked)
    }
}

struct SessionEvidenceTests {
    @Test func optionalLockFlagAbsentOnValidConsoleIsUnlocked() {
        #expect(SessionEvidence.reducer(info: [kCGSessionOnConsoleKey as String: true]).availability.isAvailable)
    }
    @Test func explicitLockAndUnknownEvidenceRemainUnavailable() {
        #expect(!SessionEvidence.reducer(info: [kCGSessionOnConsoleKey as String: true, "CGSSessionScreenIsLocked": true]).availability.isAvailable)
        #expect(!SessionEvidence.reducer(info: nil).availability.isAvailable)
        #expect(!SessionEvidence.reducer(info: [:]).availability.isAvailable)
        #expect(!SessionEvidence.reducer(info: [kCGSessionOnConsoleKey as String: true, "CGSSessionScreenIsLocked": "bad"]).availability.isAvailable)
        var switchedOut = SessionEvidence.reducer(info: [kCGSessionOnConsoleKey as String: false])
        #expect(!switchedOut.availability.isAvailable)
        #expect(switchedOut.update(.sessionActive).isAvailable)
    }
}
