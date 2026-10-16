import Foundation
import Testing
import PauseGuardCore
import PauseGuardPlatform
@testable import PauseGuardApp

@MainActor private final class Desktop: SystemEventSource {
    var currentAvailability = Availability(sleeping: false, locked: false)
    var callback: (@MainActor (Availability) -> Void)?
    func start(onAvailability: @escaping @MainActor (Availability) -> Void) { callback = onAvailability }
    func stop() { callback = nil }
}
@MainActor private final class Clock {
    var uptime: TimeInterval = 100
    func sample() -> ClockSnapshot { ClockSnapshot(continuousUptime: uptime, bootID: "test", wallDate: Date(timeIntervalSince1970: uptime)) }
}
@MainActor struct AppControllerTests {
    private func store() -> StateStore { StateStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) }
    @Test func startPauseEmergencyAndShutdownPersistIntent() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let clock = Clock()
        let controller = AppController(store: store, clock: clock.sample, idleSeconds: { 0 }, systemEvents: Desktop(), startTimer: false)
        #expect(controller.runtime.phase == .stopped)
        controller.send(.start)
        #expect(store.loadSession()?.desiredRunning == true)
        controller.send(.pause)
        #expect(store.loadSession()?.runtime.phase == .paused)
        #expect(store.loadSession()?.desiredRunning == true)
        controller.send(.resume)
        controller.send(.beginBreak)
        controller.send(.stop)
        controller.send(.pause)
        #expect(controller.runtime.phase == .breaking)
        controller.send(.emergencyRelease)
        #expect(controller.runtime.phase == .paused)
        #expect(store.loadSession()?.runtime.pausedPhase == .breaking)
        controller.shutdown()
        #expect(store.loadSession()?.desiredRunning == false)
        let next = AppController(store: store, clock: clock.sample, idleSeconds: { 0 }, systemEvents: Desktop(), startTimer: false)
        #expect(next.runtime.phase == .stopped)
        next.shutdown()
    }
    @Test func presentationFailureBypassesStrictPauseGateAndPersistsError() {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let clock = Clock()
        let controller = AppController(store: store, clock: clock.sample, idleSeconds: { 0 }, systemEvents: Desktop(), startTimer: false)
        controller.send(.start); controller.send(.beginBreak)
        controller.presentationFailed(CocoaError(.fileReadUnknown))
        #expect(controller.runtime.phase == .paused)
        #expect(controller.runtime.pausedPhase == .breaking)
        #expect(controller.lastError != nil)
        #expect(store.loadSession()?.runtime.phase == .paused)
        controller.shutdown()
    }
    @Test func stopAtWorkExpiryCannotSkipBreak() {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let clock = Clock()
        let controller = AppController(store: store, clock: clock.sample, idleSeconds: { 0 }, systemEvents: Desktop(), startTimer: false)
        controller.send(.start)
        clock.uptime = 2800
        controller.send(.stop)
        #expect(controller.runtime.phase == .breaking)
        #expect(store.loadSession()?.desiredRunning == true)
        #expect(!controller.requestQuit())
        #expect(store.loadSession()?.desiredRunning == true)
        controller.shutdown()
        #expect(store.loadSession()?.desiredRunning == false)
    }
    @Test func checkpointAndSettingsBoundaries() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let clock = Clock(); let desktop = Desktop()
        let controller = AppController(store: store, clock: clock.sample, idleSeconds: { 0 }, systemEvents: desktop, startTimer: false)
        controller.send(.start)
        clock.uptime = 104; controller.send(.tick(idleSeconds: 0))
        #expect(store.loadSession()?.clock.continuousUptime == 100)
        clock.uptime = 105; controller.send(.tick(idleSeconds: 0))
        #expect(store.loadSession()?.clock.continuousUptime == 105)
        controller.updateSettings(UserSettings(workDurationSeconds: 600, breakDurationSeconds: 60))
        #expect(store.loadSettings().workDurationSeconds == 600)
        #expect(controller.runtime.cycleSettings.workDurationSeconds == 2700)
        controller.send(.beginBreak)
        #expect(store.loadSession()?.runtime.breakRemainingSeconds == 60)
        desktop.callback?(Availability(sleeping: true, locked: false))
        #expect(store.loadSession()?.runtime.sleeping == true)
        controller.shutdown()
    }
    @Test func stoppedSessionDoesNotRelaunchAndPersistenceErrorsAreVisible() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let clock = Clock()
        let controller = AppController(store: store, clock: clock.sample, idleSeconds: { 0 }, systemEvents: Desktop(), startTimer: false)
        controller.send(.start)
        controller.send(.stop)
        #expect(store.loadSession()?.desiredRunning == false)
        #expect(store.loadSession()?.runtime.phase == .stopped)
        #expect(controller.requestQuit())
        let badURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("blocked".utf8).write(to: badURL)
        defer { try? FileManager.default.removeItem(at: badURL) }
        let failed = AppController(store: StateStore(directory: badURL), clock: clock.sample, idleSeconds: { 0 }, systemEvents: Desktop(), startTimer: false)
        #expect(failed.lastError != nil)
        failed.shutdown()
    }
    @Test func pausedRecoveryPreservesIntentAndCurrentSettings() throws {
        let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let clock = Clock()
        var engine = TimerEngine(settings: UserSettings())
        engine.handle(.start, at: 100); engine.handle(.pause, at: 100)
        try store.saveSession(PersistedSession(runtime: engine.state, clock: clock.sample(), desiredRunning: true))
        try store.saveSettings(UserSettings(workDurationSeconds: 600))
        let controller = AppController(store: store, clock: clock.sample, idleSeconds: { 0 }, systemEvents: Desktop(), startTimer: false)
        #expect(controller.runtime.phase == .paused)
        #expect(controller.settings.workDurationSeconds == 600)
        #expect(controller.desiredRunning)
        controller.shutdown()
    }
}
