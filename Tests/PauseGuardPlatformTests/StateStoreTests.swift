import Foundation
import Testing
import PauseGuardCore
@testable import PauseGuardPlatform

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("PauseGuardTests-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
func session(phase: RuntimePhase = .breaking) -> PersistedSession {
    var runtime = RuntimeState()
    runtime.phase = phase
    runtime.cycleNumber = 1
    runtime.breakRemainingSeconds = 200
    return PersistedSession(runtime: runtime, clock: ClockSnapshot(continuousUptime: 1000, bootID: "boot-a", wallDate: Date(timeIntervalSince1970: 10000)), desiredRunning: true)
}

struct StateStoreTests {
    @Test func testMissingPausedPhaseJSONIsRejected() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var saved = session(phase: .paused)
        saved.runtime.pausedPhase = nil
        let bytes = try JSONEncoder().encode(saved)
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let runtime = try #require(object["runtime"] as? [String: Any])
        #expect(runtime["pausedPhase"] == nil)
        try bytes.write(to: directory.appendingPathComponent("session.json"))
        #expect(StateStore(directory: directory).loadSession() == nil)
    }
    @Test func testValidPausedPhasesRoundTripAndResume() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory)
        for phase: RuntimePhase in [.working, .preparing, .breaking] {
            var saved = session(phase: .paused)
            saved.runtime.pausedPhase = phase
            try store.saveSession(saved)
            let loaded = try #require(store.loadSession())
            let restored = RecoveryPolicy.restore(loaded, now: saved.clock)
            #expect(restored.phase == .paused)
            #expect(restored.pausedPhase == phase)
            var engine = TimerEngine(restoring: restored, settings: UserSettings(), at: 1000)
            engine.handle(.resume, at: 1000)
            #expect(engine.state.phase == phase)
            #expect(engine.state.breakRemainingSeconds == 200)
        }
    }

    @Test func testAtomicRoundTrip() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory)
        try store.saveSettings(UserSettings(workDurationSeconds: 600))
        try store.saveSession(session())
        #expect(store.loadSettings().workDurationSeconds == 600)
        #expect(store.loadSession()?.runtime.breakRemainingSeconds == 200)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == ["session.json", "settings.json"])
        let mode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o700)
        let fileMode = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("session.json").path)[.posixPermissions] as? NSNumber
        #expect(fileMode?.intValue == 0o600)
    }
    @Test func testCorruptSettingsFallBack() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("broken".utf8)
        let url = directory.appendingPathComponent("settings.json")
        try bytes.write(to: url)
        #expect(StateStore(directory: directory).loadSettings() == UserSettings())
        #expect(try Data(contentsOf: url) == bytes)
        let store = StateStore(directory: directory)
        try store.saveSettings(UserSettings())
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("settings.json.preserved-") }
        #expect(try Data(contentsOf: #require(preserved.first)) == bytes)
    }
    @Test func testCorruptSessionDoesNotStart() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{}".utf8).write(to: directory.appendingPathComponent("session.json"))
        #expect(StateStore(directory: directory).loadSession() == nil)
    }
    @Test func testUnsupportedVersionIsPreserved() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var future = session()
        future.schemaVersion = 999
        let url = directory.appendingPathComponent("session.json")
        let bytes = try JSONEncoder().encode(future)
        try bytes.write(to: url)
        let store = StateStore(directory: directory)
        #expect(store.loadSession() == nil)
        #expect(try Data(contentsOf: url) == bytes)
        try store.saveSession(session())
        #expect(store.loadSession()?.runtime.breakRemainingSeconds == 200)
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("session.json.preserved-") }
        #expect(preserved.count == 1)
        #expect(try Data(contentsOf: #require(preserved.first)) == bytes)
    }
    @Test func testInvalidRuntimeRejected() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var invalid = session()
        invalid.runtime.breakRemainingSeconds = -1
        let bytes = try JSONEncoder().encode(invalid)
        try bytes.write(to: directory.appendingPathComponent("session.json"))
        #expect(StateStore(directory: directory).loadSession() == nil)
    }
    @Test func testUnsupportedSettingsVersionIsPreserved() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        let bytes = Data("{\"schemaVersion\":999,\"settings\":{}}".utf8)
        try bytes.write(to: url)
        let store = StateStore(directory: directory)
        #expect(store.loadSettings() == UserSettings())
        #expect(try Data(contentsOf: url) == bytes)
        try store.saveSettings(UserSettings(workDurationSeconds: 600))
        #expect(store.loadSettings().workDurationSeconds == 600)
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("settings.json.preserved-") }
        #expect(preserved.count == 1)
        #expect(try Data(contentsOf: #require(preserved.first)) == bytes)
    }
    @Test func testSessionRejectsFutureAwayBaseline() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var saved = session(phase: .working)
        saved.runtime.sleeping = true
        saved.runtime.awayStartedAt = 2000
        try JSONEncoder().encode(saved).write(to: directory.appendingPathComponent("session.json"))
        #expect(StateStore(directory: directory).loadSession() == nil)
    }
    @Test func testEventLogIsBoundedAndPrivate() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = EventLog(directory: directory, maximumBytes: 1024)
        for _ in 0..<100 { log.append(kind: "tick\n", detail: String(repeating: "a", count: 200)) }
        let url = directory.appendingPathComponent("events.log")
        let data = try Data(contentsOf: url)
        #expect(data.count <= 1024)
        #expect(data.count > 0)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber == 0o600)
    }
}
