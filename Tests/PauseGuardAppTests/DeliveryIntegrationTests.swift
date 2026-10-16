import Foundation
import CoreGraphics
import Testing
import PauseGuardCore
import PauseGuardPlatform
@testable import PauseGuardApp

@MainActor private final class IntegrationDesktop: SystemEventSource {
    var currentAvailability = Availability(sleeping: false, locked: false)
    func start(onAvailability: @escaping @MainActor (Availability) -> Void) {}
    func stop() {}
}
@MainActor private final class IntegrationClock {
    var uptime: TimeInterval = 100
    func sample() -> ClockSnapshot {
        ClockSnapshot(continuousUptime: uptime, bootID: "delivery", wallDate: Date(timeIntervalSince1970: uptime))
    }
}
@MainActor private final class IntegrationCover: BreakCover {
    var released = false
    var defaultBackground = false
    func update(runtime: RuntimeState) {}
    func setBackground(_ image: CGImage?) { defaultBackground = image == nil }
    func release() { released = true }
}
@MainActor private final class IntegrationBackend: BreakPresentationBackend {
    let displays = [DisplayDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 80, height: 60), scale: 1, isMain: true)]
    let cover = IntegrationCover()
    func begin() {}
    func end() {}
    func makeCover(display: DisplayDescriptor, runtime: RuntimeState, onEvent: @escaping (EngineEvent) -> Void) throws -> any BreakCover { cover }
}

@Suite @MainActor struct DeliveryIntegrationTests {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    @Test func persistedSettingsDriveFreshControllerThroughCompleteCycle() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(directory: root), clock = IntegrationClock()
        try store.saveSettings(UserSettings(workDurationSeconds: 300, breakDurationSeconds: 60, strictMode: false))
        let controller = AppController(store: store, clock: clock.sample, idleSeconds: { 0 }, systemEvents: IntegrationDesktop(), startTimer: false)
        defer { controller.shutdown() }
        controller.send(.start)
        #expect(controller.runtime.workRemainingSeconds == 300)
        clock.uptime += 300; controller.send(.tick(idleSeconds: 0))
        #expect(controller.runtime.phase == .breaking)
        #expect(!controller.runtime.cycleSettings.strictMode)
        #expect(store.loadSession()?.runtime.breakRemainingSeconds == 60)
        clock.uptime += 60; controller.send(.tick(idleSeconds: 0))
        #expect(controller.runtime.phase == .working)
        #expect(controller.runtime.cycleNumber == 2)
        #expect(controller.runtime.workRemainingSeconds == 300)
    }
    @Test func corruptLibraryDoesNotDelayBreakAndDefaultCoverStillReleases() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let library = root.appendingPathComponent("Images")
        // A regular file where the library directory belongs forces real worker I/O failure.
        try Data("corrupt library".utf8).write(to: library)
        let provider = ImageBackgroundProvider(libraryURL: library)
        let backend = IntegrationBackend()
        provider.prepare(for: backend.displays)
        let controller = AppController(store: StateStore(directory: root), clock: IntegrationClock().sample, idleSeconds: { 0 }, systemEvents: IntegrationDesktop(), startTimer: false)
        let covers = BreakWindowController(backend: backend, observeScreens: false)
        defer { covers.dismiss(); controller.shutdown() }
        controller.send(.start); controller.send(.beginBreak)
        try covers.show(runtime: controller.runtime, background: provider, onEvent: controller.send)
        #expect(controller.runtime.phase == .breaking)
        #expect(backend.cover.defaultBackground)
        let image = await withCheckedContinuation { continuation in
            _ = provider.image(for: backend.displays[0]) { continuation.resume(returning: $0) }
        }
        #expect(image == nil)
        #expect(!backend.cover.released)
        covers.handle(.emergencyRelease)
        #expect(backend.cover.released)
        let saved = try #require(StateStore(directory: root).loadSession())
        #expect(saved.runtime.phase == .paused)
        #expect(saved.runtime.pausedPhase == .breaking)
        // Simulated process disappearance: the new coordinator must preserve emergency pause.
        let reopened = AppController(store: StateStore(directory: root), clock: IntegrationClock().sample, idleSeconds: { 0 }, systemEvents: IntegrationDesktop(), startTimer: false)
        #expect(reopened.runtime.phase == .paused)
        #expect(reopened.runtime.pausedPhase == .breaking)
        reopened.shutdown()
    }
    @Test func savedBreakSnapshotRestoresThroughCoordinatorAndCompletes() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(directory: root), clock = IntegrationClock()
        let settings = UserSettings(workDurationSeconds: 600, breakDurationSeconds: 120)
        try store.saveSettings(settings)
        var engine = TimerEngine(settings: settings)
        engine.handle(.start, at: 100); engine.handle(.beginBreak, at: 100)
        try store.saveSession(PersistedSession(runtime: engine.state, clock: clock.sample(), desiredRunning: true))
        clock.uptime = 130
        let controller = AppController(store: store, clock: clock.sample, idleSeconds: { 0 }, systemEvents: IntegrationDesktop(), startTimer: false)
        defer { controller.shutdown() }
        #expect(controller.runtime.phase == .breaking)
        #expect(controller.runtime.breakRemainingSeconds == 90)
        #expect(controller.desiredRunning)
        clock.uptime = 220; controller.send(.tick(idleSeconds: 0))
        #expect(controller.runtime.phase == .working)
        #expect(store.loadSession()?.runtime.workRemainingSeconds == 600)
    }
    @Test func systemTerminationPreservesUnfinishedBreakAndReleasesWithoutLaterOverwrite() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(directory: root), clock = IntegrationClock()
        let controller = AppController(store: store, clock: clock.sample, idleSeconds: { 0 }, systemEvents: IntegrationDesktop(), startTimer: false)
        let backend = IntegrationBackend()
        let model = DesktopModel(directory: root, controller: controller,
            covers: BreakWindowController(backend: backend, observeScreens: false))
        controller.send(.start); controller.send(.beginBreak)
        #expect(!model.requestTermination(systemSessionEnding: false))
        #expect(model.requestTermination(systemSessionEnding: true))
        // OS termination must not be mistaken for an explicit menu quit.
        #expect(backend.cover.released)
        #expect(store.loadSession()?.desiredRunning == true)
        model.shutdown()
        #expect(store.loadSession()?.desiredRunning == true)
        clock.uptime += 30
        let reopened = AppController(store: store, clock: clock.sample, idleSeconds: { 0 }, systemEvents: IntegrationDesktop(), startTimer: false)
        #expect(reopened.runtime.phase == .breaking)
        #expect(reopened.runtime.breakRemainingSeconds == 270)
        reopened.shutdown()
    }

}
