import Testing
import Foundation
import CoreGraphics
import PauseGuardCore
import PauseGuardPlatform
@testable import PauseGuardApp

@MainActor private final class MemoryCover: BreakCover {
    var released = false
    var images = 0
    func update(runtime: RuntimeState) {}
    func setBackground(_ image: CGImage?) { images += 1 }
    func release() { released = true }
}
@MainActor private final class MemoryBackend: BreakPresentationBackend {
    var displays = [DisplayDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1, isMain: true)]
    var covers: [MemoryCover] = []
    var callbacks: [(EngineEvent) -> Void] = []
    var failID: UInt32?
    var active = false
    func begin() { active = true }
    func end() { active = false }
    func makeCover(display: DisplayDescriptor, runtime: RuntimeState, onEvent: @escaping (EngineEvent) -> Void) throws -> any BreakCover {
        if failID == display.id { throw CocoaError(.fileReadUnknown) }
        let cover = MemoryCover(); covers.append(cover); callbacks.append(onEvent); return cover
    }
}
@MainActor private final class DelayedBackground: BackgroundProvider {
    var callbacks: [@MainActor (CGImage?) -> Void] = []
    func image(for display: DisplayDescriptor, completion: @escaping @MainActor (CGImage?) -> Void) -> CGImage? {
        callbacks.append(completion); return nil
    }
}
@Suite @MainActor struct BreakWindowControllerTests {
    func runtime(_ cycle: Int = 1) -> RuntimeState {
        var value = RuntimeState(); value.phase = .breaking; value.cycleNumber = cycle; return value
    }
    @Test func droppingOwnerReleasesCoversAndPresentationOptions() throws {
        let backend = MemoryBackend(), background = DelayedBackground()
        var controller: BreakWindowController? = BreakWindowController(backend: backend, observeScreens: false)
        try controller?.show(runtime: runtime(), background: background, onEvent: { _ in })
        controller = nil
        #expect(backend.covers[0].released)
        #expect(!backend.active)
    }
    @Test func lateBackgroundCannotChangeDismissedOrNewCycle() throws {
        let backend = MemoryBackend(), background = DelayedBackground()
        let controller = BreakWindowController(backend: backend, observeScreens: false)
        try controller.show(runtime: runtime(), background: background, onEvent: { _ in })
        let old = backend.covers[0]
        controller.dismiss(); controller.dismiss()
        try controller.show(runtime: runtime(2), background: background, onEvent: { _ in })
        background.callbacks[0](nil)
        backend.callbacks[0](.emergencyRelease)
        #expect(backend.active)
        #expect(!backend.covers[1].released)
        #expect(old.released)
        #expect(old.images == 1)
        #expect(backend.covers[1].images == 1)
        controller.dismiss()
        #expect(!backend.active)
    }
    @Test func partialFailureReleasesEverythingBeforeFailureCallback() {
        let backend = MemoryBackend(), background = DelayedBackground()
        backend.displays.append(DisplayDescriptor(id: 2, frame: .zero, scale: 1, isMain: false)); backend.failID = 2
        let controller = BreakWindowController(backend: backend, observeScreens: false)
        var failureCount = 0
        controller.onFailure = { _ in
            #expect(!backend.active)
            #expect(backend.covers.allSatisfy { $0.released })
            failureCount += 1
        }
        #expect(throws: (any Error).self) { try controller.show(runtime: runtime(), background: background, onEvent: { _ in }) }
        #expect(failureCount == 1)
    }
    @Test func hotPlugReleasesOnlyRemovedAndUnavailableDismisses() throws {
        let backend = MemoryBackend(), background = DelayedBackground()
        let controller = BreakWindowController(backend: backend, observeScreens: false)
        try controller.show(runtime: runtime(), background: background, onEvent: { _ in })
        backend.displays.append(DisplayDescriptor(id: 2, frame: .zero, scale: 1, isMain: false))
        controller.screensChanged()
        #expect(backend.covers.count == 2)
        #expect(!backend.covers[0].released)
        backend.displays.removeFirst(); controller.screensChanged()
        #expect(backend.covers[0].released)
        #expect(!backend.covers[1].released)
        var locked = runtime(); locked.locked = true
        controller.update(runtime: locked)
        #expect(backend.covers[1].released)
        #expect(!backend.active)
    }
    @Test func emptyTopologyFailsAndReleases() throws {
        let backend = MemoryBackend(), background = DelayedBackground()
        let controller = BreakWindowController(backend: backend, observeScreens: false)
        try controller.show(runtime: runtime(), background: background, onEvent: { _ in })
        var failed = false; controller.onFailure = { _ in failed = true }
        backend.displays = []; controller.screensChanged()
        #expect(failed)
        #expect(backend.covers[0].released)
        #expect(!backend.active)
    }
    @Test func nonStrictEndReleasesBeforeCoordinator() throws {
        let backend = MemoryBackend(), background = DelayedBackground()
        let controller = BreakWindowController(backend: backend, observeScreens: false)
        var state = runtime(); state.cycleSettings.strictMode = false
        var ended = false
        try controller.show(runtime: state, background: background, onEvent: { event in
            #expect(!backend.active)
            #expect(event == .endBreak)
            ended = true
        })
        controller.handle(.endBreak)
        #expect(ended)
    }
    @Test func staleActionsCannotReleaseNewCycleAndStrictEndIsRejected() throws {
        let backend = MemoryBackend(), background = DelayedBackground()
        let controller = BreakWindowController(backend: backend, observeScreens: false)
        var events: [EngineEvent] = []
        try controller.show(runtime: runtime(), background: background, onEvent: { events.append($0) })
        controller.handle(.endBreak)
        #expect(events.isEmpty)
        controller.handle(.emergencyRelease)
        #expect(events == [.emergencyRelease])
        #expect(backend.covers[0].released)
        #expect(!backend.active)
    }
}
