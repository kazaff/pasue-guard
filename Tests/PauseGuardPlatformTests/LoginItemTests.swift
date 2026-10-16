import Foundation
import Testing
@testable import PauseGuardPlatform

struct LoginItemTests {
    @Test func testPlistUsesStructuredArgumentsAndCurrentUserPaths() throws {
        let home = URL(fileURLWithPath: "/tmp/home with space & quote'")
        let app = URL(fileURLWithPath: "/Applications/休息 & Focus.app")
        let manager = LoginItemManager(homeDirectory: home, runLaunchctl: { _ in })
        let data = try manager.plistData(appURL: app)
        let value = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(value["ProgramArguments"] as? [String] == ["/Applications/休息 & Focus.app/Contents/MacOS/PauseGuardAgent", "--app", "/Applications/休息 & Focus.app"])
        #expect(manager.plistURL.path == "/tmp/home with space & quote'/Library/LaunchAgents/com.pauseguard.agent.plist")
        #expect(value["RunAtLoad"] as? Bool == true)
        let starter = try #require(PropertyListSerialization.propertyList(from: manager.plistData(appURL: app, loginStarter: true), format: nil) as? [String: Any])
        #expect(starter["ProgramArguments"] as? [String] == ["/usr/bin/open", "-g", "/Applications/休息 & Focus.app"])
        #expect(starter["KeepAlive"] as? Bool == false)
    }
    @Test func testInstallAndRemovalInTemporaryHome() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let app = home.appendingPathComponent("Test App.app")
        let executable = app.appendingPathComponent("Contents/MacOS/PauseGuardAgent")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let history = AgentHistoryStore(directory: home.appendingPathComponent("Library/Application Support/PauseGuard"))
        var exhausted = AgentRecoveryPolicy()
        let session = AgentRecoveryTests().saved()
        for _ in 0..<3 { _ = exhausted.decision(session: session, appRunning: false, now: Date()) }
        try history.save(exhausted)
        let manager = LoginItemManager(homeDirectory: home, runLaunchctl: { _ in })
        try manager.setEnabled(true, appURL: app)
        var reset = history.load()
        #expect(reset.decision(session: session, appRunning: false, now: Date()) == .relaunch)
        #expect(FileManager.default.fileExists(atPath: manager.plistURL.path))
        #expect(FileManager.default.fileExists(atPath: manager.loginPlistURL.path))
        try manager.setEnabled(false, appURL: app)
        #expect(!FileManager.default.fileExists(atPath: manager.plistURL.path))
        #expect(!FileManager.default.fileExists(atPath: manager.loginPlistURL.path))
    }
    @Test func testSecondJobFailureRollsBackBothFilesAndLoadedGuardian() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let app = home.appendingPathComponent("Test.app")
        let exe = app.appendingPathComponent("Contents/MacOS/PauseGuardAgent")
        try FileManager.default.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exe.path)
        let history = AgentHistoryStore(directory: home.appendingPathComponent("Library/Application Support/PauseGuard"))
        var exhausted = AgentRecoveryPolicy()
        let session = AgentRecoveryTests().saved()
        for _ in 0..<3 { _ = exhausted.decision(session: session, appRunning: false, now: Date()) }
        try history.save(exhausted)
        var calls: [[String]] = []
        let manager = LoginItemManager(homeDirectory: home, runLaunchctl: { args in
            calls.append(args)
            if calls.count == 2 { throw CocoaError(.executableLoad) }
        })
        #expect(throws: (any Error).self) { try manager.setEnabled(true, appURL: app) }
        #expect(!FileManager.default.fileExists(atPath: manager.plistURL.path))
        #expect(!FileManager.default.fileExists(atPath: manager.loginPlistURL.path))
        var unchanged = history.load()
        #expect(unchanged.decision(session: session, appRunning: false, now: Date().addingTimeInterval(86400)) == .stopRetrying)
        #expect(calls.last?.first == "bootout")
        #expect(calls.last?.last?.hasSuffix("/com.pauseguard.agent") == true)
    }
    @Test func testRollbackFileRemovalFailureReportsRemainingPathsAndCanRetry() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let app = home.appendingPathComponent("Test.app")
        let executable = app.appendingPathComponent("Contents/MacOS/PauseGuardAgent")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        var denyCleanup = true
        let manager = LoginItemManager(homeDirectory: home, runLaunchctl: { arguments in
            if arguments.first == "bootstrap", arguments.last?.hasSuffix("com.pauseguard.login.plist") == true {
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "bootstrap-denied"])
            }
        }, removeFile: { url in
            if denyCleanup { throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "remove-denied"]) }
            try FileManager.default.removeItem(at: url)
        })
        do {
            try manager.setEnabled(true, appURL: app)
            Issue.record("Expected bootstrap failure")
        } catch {
            #expect(error.localizedDescription.contains("bootstrap-denied"))
            #expect(error.localizedDescription.contains("remove-denied"))
            #expect(error.localizedDescription.contains(manager.plistURL.path))
            #expect(error.localizedDescription.contains(manager.loginPlistURL.path))
        }
        #expect(manager.remainingPaths.count == 2)
        denyCleanup = false
        try manager.setEnabled(false, appURL: app)
        #expect(manager.remainingPaths.isEmpty)
    }
    @Test func testUnloadedOneShotJobCanStillBeRemoved() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let manager = LoginItemManager(homeDirectory: home, runLaunchctl: { _ in
            throw NSError(domain: "PauseGuard.LoginItem", code: 3)
        })
        try FileManager.default.createDirectory(at: manager.loginPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: manager.loginPlistURL)
        try manager.setEnabled(false, appURL: home.appendingPathComponent("Unused.app"))
        #expect(!FileManager.default.fileExists(atPath: manager.loginPlistURL.path))
    }
    @Test func testFailureRollsBackNewInstallationAndRejectsNonBundle() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let manager = LoginItemManager(homeDirectory: home, runLaunchctl: { _ in throw CocoaError(.executableLoad) })
        #expect(throws: (any Error).self) { try manager.plistData(appURL: home) }
        let app = home.appendingPathComponent("Test.app")
        let exe = app.appendingPathComponent("Contents/MacOS/PauseGuardAgent")
        try FileManager.default.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exe.path)
        #expect(throws: (any Error).self) { try manager.setEnabled(true, appURL: app) }
        #expect(!FileManager.default.fileExists(atPath: manager.plistURL.path))
        #expect(!FileManager.default.fileExists(atPath: manager.loginPlistURL.path))
    }
}
