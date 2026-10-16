import AppKit
import Combine
import Foundation
import Testing
import PauseGuardCore
import PauseGuardPlatform
@testable import PauseGuardApp

@MainActor private final class AvailableDesktop: SystemEventSource {
    var currentAvailability = Availability(sleeping: false, locked: false)
    func start(onAvailability: @escaping @MainActor (Availability) -> Void) {}
    func stop() {}
}
@MainActor private final class MissingDisplaysBackend: BreakPresentationBackend {
    var displays: [DisplayDescriptor] { [] }
    var starts = 0
    func begin() { starts += 1 }
    func end() {}
    func makeCover(display: DisplayDescriptor, runtime: RuntimeState,
                   onEvent: @escaping (EngineEvent) -> Void) throws -> any BreakCover { fatalError("No displays") }
}
@Suite @MainActor struct DesktopModelIntegrationTests {
    @Test func loginConsentPersistsOnlyAfterSuccessAndDemoNeverInstalls() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = AppController(store: StateStore(directory: directory), idleSeconds: { 0 }, systemEvents: AvailableDesktop(), startTimer: false)
        var shouldFail = true
        var calls = 0
        let model = DesktopModel(directory: directory, controller: controller,
            covers: BreakWindowController(backend: MissingDisplaysBackend(), observeScreens: false),
            setLoginEnabled: { _ in calls += 1; if shouldFail { throw CocoaError(.executableLoad) } })
        defer { model.shutdown() }
        #expect(!model.preferences.loginAtLaunch)
        #expect(calls == 0)
        model.setLoginAtLaunch(true)
        #expect(!model.preferences.loginAtLaunch)
        #expect(!PreferencesStore(directory: directory).load().loginAtLaunch)
        #expect(model.error != nil)
        shouldFail = false
        model.setLoginAtLaunch(true)
        #expect(model.preferences.loginAtLaunch)
        #expect(PreferencesStore(directory: directory).load().loginAtLaunch)
        #expect(model.error == nil)
        let demo = DesktopModel(demo: true, directory: directory.appendingPathComponent("demo"), controller: controller,
            covers: BreakWindowController(backend: MissingDisplaysBackend(), observeScreens: false),
            setLoginEnabled: { _ in calls += 100 })
        demo.setLoginAtLaunch(true)
        #expect(!demo.preferences.loginAtLaunch)
        #expect(calls == 2)
    }
    @Test func preferenceSaveAndLoginRollbackFailuresRemainVisibleAndRemovalCanRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("PauseGuard.app")
        let agent = app.appendingPathComponent("Contents/MacOS/PauseGuardAgent")
        try FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: agent)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: agent.path)
        var denyRemoval = true
        let manager = LoginItemManager(homeDirectory: directory, runLaunchctl: { arguments in
            if arguments.first == "bootout", denyRemoval {
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "bootout-denied"])
            }
        })
        let controller = AppController(store: StateStore(directory: directory), idleSeconds: { 0 }, systemEvents: AvailableDesktop(), startTimer: false)
        let model = DesktopModel(directory: directory, controller: controller,
            covers: BreakWindowController(backend: MissingDisplaysBackend(), observeScreens: false),
            setLoginEnabled: { try manager.setEnabled($0, appURL: app) },
            loginItemPaths: { manager.remainingPaths })
        defer { model.shutdown() }
        // A directory in place of preferences.json deterministically rejects a real preference save.
        let preferencePath = directory.appendingPathComponent("preferences.json")
        try FileManager.default.createDirectory(at: preferencePath, withIntermediateDirectories: true)
        model.setLoginAtLaunch(true)
        #expect(FileManager.default.fileExists(atPath: manager.plistURL.path))
        #expect(FileManager.default.fileExists(atPath: manager.loginPlistURL.path))
        #expect(model.error?.contains("bootout-denied") == true)
        #expect(model.loginItemInstalled)
        #expect(model.loginCleanupRequired)
        #expect(model.loginCleanupPaths.contains(manager.plistURL.path))
        #expect(!model.preferences.loginAtLaunch)
        #expect(!PreferencesStore(directory: directory).load().loginAtLaunch)
        #expect(model.error?.contains(CocoaError(.fileWriteInvalidFileName).localizedDescription) == true)
        denyRemoval = false
        // Cleanup must succeed even while the saved preference is already false and storage remains broken.
        model.retryLoginCleanup()
        #expect(!model.loginItemInstalled)
        #expect(!model.loginCleanupRequired)
        #expect(model.loginCleanupPaths.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: manager.plistURL.path))
        #expect(!FileManager.default.fileExists(atPath: manager.loginPlistURL.path))
        #expect(model.error == nil)
    }
    @Test func presentationFailureAfterRuntimePublicationPersistsPausedStateOnce() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory)
        let controller = AppController(store: store,
            clock: { ClockSnapshot(continuousUptime: 100, bootID: "integration", wallDate: Date(timeIntervalSince1970: 100)) },
            idleSeconds: { 0 }, systemEvents: AvailableDesktop(), startTimer: false)
        let backend = MissingDisplaysBackend()
        let covers = BreakWindowController(backend: backend, observeScreens: false)
        let model = DesktopModel(directory: directory, controller: controller, covers: covers)
        defer { model.shutdown() }
        var errors = 0
        let errorSubscription = controller.$lastError.compactMap { $0 }.sink { _ in errors += 1 }
        defer { errorSubscription.cancel() }
        controller.send(.start)
        controller.send(.beginBreak)
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.runtime.phase == .paused)
        #expect(controller.runtime.pausedPhase == .breaking)
        #expect(store.loadSession()?.runtime.phase == .paused)
        #expect(store.loadSession()?.runtime.pausedPhase == .breaking)
        #expect(errors == 1)
        #expect(backend.starts == 1)
        controller.send(.tick(idleSeconds: 0))
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.runtime.phase == .paused)
        #expect(store.loadSession()?.runtime.phase == .paused)
        #expect(errors == 1)
        #expect(backend.starts == 1)
    }
}
