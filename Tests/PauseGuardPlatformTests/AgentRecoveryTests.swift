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
        #expect(policy.decision(session: saved(), appRunning: false, now: now.addingTimeInterval(300)) == .stopRetrying)
        #expect(policy.decision(session: saved(), appRunning: false, now: now.addingTimeInterval(86400)) == .stopRetrying)
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
        #expect(restarted.decision(session: saved(), appRunning: false, now: now.addingTimeInterval(86400)) == .stopRetrying)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("session.json").path))
        try Data("broken".utf8).write(to: root.appendingPathComponent("agent-history.json"))
        var corrupt = store.load()
        #expect(corrupt.decision(session: saved(), appRunning: false, now: now) == .stopRetrying)
    }
    @Test func testLegacyAndFutureHistoryFailClosed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for json in [#"{"attempts":[],"blocked":false}"#, #"{"schemaVersion":999,"attempts":[],"blocked":false}"#] {
            try Data(json.utf8).write(to: root.appendingPathComponent("agent-history.json"))
            var policy = AgentHistoryStore(directory: root).load()
            #expect(policy.decision(session: saved(), appRunning: false, now: now) == .stopRetrying)
        }
    }
    @Test func testBackwardClockDoesNotGrantExtraRetries() {
        var policy = AgentRecoveryPolicy()
        for _ in 0..<3 { _ = policy.decision(session: saved(), appRunning: false, now: now) }
        #expect(policy.decision(session: saved(), appRunning: false, now: now.addingTimeInterval(-10000)) == .stopRetrying)
    }
}

struct AgentPollingIntegrationTests {
    @Test func testPollingChargesAndPersistsStopAcrossRestartsUntilExplicitEnable() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent("Library/Application Support/PauseGuard")
        let session = AgentRecoveryTests().saved()
        let start = Date(timeIntervalSince1970: 1000)
        for seconds in [0.0, 400, 800] {
            #expect(try AgentHistoryStore(directory: root).decision(session: session, appRunning: false, now: start.addingTimeInterval(seconds)) == .relaunch)
        }
        let store = AgentHistoryStore(directory: root)
        #expect(try store.decision(session: session, appRunning: false, now: start.addingTimeInterval(1200)) == .stopRetrying)
        let value = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("agent-history.json"))) as? [String: Any])
        #expect(value["blocked"] as? Bool == true)
        #expect(try AgentHistoryStore(directory: root).decision(session: session, appRunning: false, now: start.addingTimeInterval(86400)) == .stopRetrying)
        #expect(try store.decision(session: AgentRecoveryTests().saved(false), appRunning: false, now: start) == .none)
        #expect(try store.decision(session: session, appRunning: true, now: start) == .none)
        #expect(try store.decision(session: session, appRunning: false, now: start.addingTimeInterval(172800)) == .stopRetrying)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("session.json").path))
        try store.resetAfterExplicitEnable()
        #expect(try store.decision(session: session, appRunning: false, now: start) == .relaunch)
    }
    @Test func testPollingNeverAuthorizesLaunchWhenDurableChargeFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a directory".utf8).write(to: root)
        #expect(throws: (any Error).self) {
            try AgentHistoryStore(directory: root).decision(session: AgentRecoveryTests().saved(), appRunning: false, now: Date())
        }
    }
    @Test func testExplicitResetPreservesIncompatibleHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bytes = Data(#"{"schemaVersion":999,"attempts":[],"blocked":false}"#.utf8)
        try bytes.write(to: root.appendingPathComponent("agent-history.json"))
        let store = AgentHistoryStore(directory: root)
        #expect(try store.decision(session: AgentRecoveryTests().saved(), appRunning: false, now: Date()) == .stopRetrying)
        #expect(try Data(contentsOf: root.appendingPathComponent("agent-history.json")) == bytes)
        try store.resetAfterExplicitEnable()
        #expect(try store.decision(session: AgentRecoveryTests().saved(), appRunning: false, now: Date()) == .relaunch)
        let evidence = try #require(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("agent-history.json.preserved-") })
        #expect(try Data(contentsOf: evidence) == bytes)
    }
}
