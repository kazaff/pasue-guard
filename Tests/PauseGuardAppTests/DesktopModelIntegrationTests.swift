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
