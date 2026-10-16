import Foundation
import Testing
import PauseGuardCore
@testable import PauseGuardPlatform

struct AgentRecoveryTests {
    let now = Date(timeIntervalSince1970: 1000)
    func saved(_ desired: Bool = true) -> PersistedSession {
        PersistedSession(runtime: TimerEngine(settings: UserSettings()).state,
                         clock: ClockSnapshot(continuousUptime: 0, bootID: "test", wallDate: now), desiredRunning: desired)
    }
    @Test func testExplicitExitDoesNotRestart() {
        var policy = AgentRecoveryPolicy()
        #expect(policy.decision(session: saved(false), appRunning: false, now: now) == .none)
    }
    @Test func testMissingOrCorruptStateDoesNotRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var policy = AgentRecoveryPolicy()
        #expect(policy.decision(session: StateStore(directory: root).loadSession(), appRunning: false, now: now) == .none)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: root.appendingPathComponent("session.json"))
        #expect(policy.decision(session: StateStore(directory: root).loadSession(), appRunning: false, now: now) == .none)
    }
    @Test func testThreeFailuresWithinFiveMinutesStopRetrying() {
        var policy = AgentRecoveryPolicy()
        for second in [0.0, 10, 20] {
            #expect(policy.decision(session: saved(), appRunning: false, now: now.addingTimeInterval(second)) == .relaunch)
        }
        #expect(policy.decision(session: saved(), appRunning: false, now: now.addingTimeInterval(299)) == .stopRetrying)
        #expect(policy.decision(session: saved(), appRunning: false, now: now.addingTimeInterval(300)) == .relaunch)
    }
    @Test func testLiveProcessDoesNotDuplicate() {
        var policy = AgentRecoveryPolicy()
        #expect(policy.decision(session: saved(), appRunning: true, now: now) == .none)
        #expect(policy.attempts.isEmpty)
    }
    @Test func testRetryHistorySurvivesAgentRestartAndFailsClosedOnCorruption() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentHistoryStore(directory: root)
        var policy = store.load()
        for _ in 0..<3 { _ = policy.decision(session: saved(), appRunning: false, now: now) }
        try store.save(policy)
        var restarted = store.load()
        #expect(restarted.decision(session: saved(), appRunning: false, now: now) == .stopRetrying)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("session.json").path))
        try Data("broken".utf8).write(to: root.appendingPathComponent("agent-history.json"))
        var corrupt = store.load()
        #expect(corrupt.decision(session: saved(), appRunning: false, now: now) == .stopRetrying)
    }
    @Test func testBackwardClockDoesNotGrantExtraRetries() {
        var policy = AgentRecoveryPolicy()
        for _ in 0..<3 { _ = policy.decision(session: saved(), appRunning: false, now: now) }
        #expect(policy.decision(session: saved(), appRunning: false, now: now.addingTimeInterval(-10000)) == .stopRetrying)
    }
}
