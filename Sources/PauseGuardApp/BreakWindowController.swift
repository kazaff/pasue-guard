import AppKit
import SwiftUI
import PauseGuardCore
import PauseGuardPlatform

@MainActor public protocol BackgroundProvider: AnyObject {
    /// Returns a ready image or nil for the built-in background without waiting.
    /// Completion may arrive late; the presentation owner must guard its lifetime.
    func image(for display: DisplayDescriptor, completion: @escaping @MainActor (CGImage?) -> Void) -> CGImage?
}

@MainActor protocol BreakCover: AnyObject {
    func update(runtime: RuntimeState)
    func setBackground(_ image: CGImage?)
    func release()
}
@MainActor protocol BreakPresentationBackend: AnyObject {
    var displays: [DisplayDescriptor] { get }
    func begin()
    func setStrictMode(_ strict: Bool)
    func end()
    func makeCover(display: DisplayDescriptor, runtime: RuntimeState,
                   onEvent: @escaping (EngineEvent) -> Void) throws -> any BreakCover
}

extension BreakPresentationBackend { func setStrictMode(_ strict: Bool) {} }

/// Lifecycle owner in the main app only. Creating this object never creates windows.
@MainActor public final class BreakWindowController {
    public var onFailure: ((Error) -> Void)?
    public var message = "让目光看向远处，放松肩膀，起身活动。"
    public var reduceVisualStimulation = false
    private let backend: any BreakPresentationBackend
    private var covers: [UInt32: any BreakCover] = [:]
    private var descriptors: [DisplayDescriptor] = []
    private var background: (any BackgroundProvider)?
    private var runtime: RuntimeState?
    private var onEvent: ((EngineEvent) -> Void)?
    private var generation = UUID()
    private var observer: NSObjectProtocol?
    private let observeScreens: Bool
    public convenience init() { self.init(backend: AppKitBreakBackend(), observeScreens: true) }
    init(backend: any BreakPresentationBackend, observeScreens: Bool) {
        self.backend = backend; self.observeScreens = observeScreens
    }

    isolated deinit { dismiss() }

    public func show(runtime: RuntimeState, background: any BackgroundProvider,
                     onEvent: @escaping (EngineEvent) -> Void) throws {
        guard runtime.phase == .breaking, runtime.isAvailable else { dismiss(); return }
        if self.runtime?.cycleNumber == runtime.cycleNumber {
            update(runtime: runtime); return
        }
        dismiss()
        self.runtime = runtime; self.background = background; self.onEvent = onEvent
        backend.setStrictMode(runtime.cycleSettings.strictMode)
        backend.begin()
        do {
            try reconcile()
            if observeScreens {
                observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                  object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.screensChanged() }
                }
            }
        } catch { fail(error); throw error }
    }

    public func update(runtime: RuntimeState) {
        guard runtime.phase == .breaking, runtime.isAvailable,
              self.runtime?.cycleNumber == runtime.cycleNumber else { dismiss(); return }
        self.runtime = runtime
        covers.values.forEach { $0.update(runtime: runtime) }
    }
    public func dismiss() {
        generation = UUID()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        covers.values.forEach { $0.release() }; covers.removeAll()
        descriptors = []; runtime = nil; background = nil; onEvent = nil
        backend.end()
    }
    func handle(_ event: EngineEvent) {
        guard let runtime else { return }
        switch event {
        case .endBreak:
            guard !runtime.cycleSettings.strictMode else { return }
        case .emergencyRelease: break
        default: return
        }
        let callback = onEvent
        dismiss() // Release before calling the coordinator, even if it fails.
        callback?(event)
    }
    func screensChanged() {
        guard runtime != nil else { return }
        do { try reconcile() } catch { fail(error) }
    }
    private func fail(_ error: Error) {
        dismiss()
        onFailure?(error)
    }
    private func reconcile() throws {
        guard let runtime, let background else { return }
        let displays = backend.displays
        guard !displays.isEmpty else { throw PresentationError.noDisplays }
        let changes = DisplayTopology.diff(previous: descriptors, current: displays)
        for descriptor in changes.removed + changes.updated {
            covers.removeValue(forKey: descriptor.id)?.release()
        }
        let token = generation
        for descriptor in changes.added + changes.updated {
            let cover = try backend.makeCover(display: descriptor, runtime: runtime) { [weak self] event in
                guard let self, self.generation == token else { return }
                self.handle(event)
            }
            (cover as? AppKitBreakCover)?.configure(message: message, reduceVisualStimulation: reduceVisualStimulation)
            covers[descriptor.id] = cover
            let image = background.image(for: descriptor) { [weak self, weak cover] image in
                guard let self, self.generation == token,
                      let cover, let current = self.covers[descriptor.id], current === cover else { return }
                cover.setBackground(image)
            }
            cover.setBackground(image)
        }
        descriptors = displays
    }
    enum PresentationError: LocalizedError {
        case noDisplays, missingScreen
        var errorDescription: String? {
            "无法为所有显示器建立休息窗口，覆盖已解除。请检查显示器连接后手动恢复循环。"
        }
    }
}

@MainActor final class AppKitBreakBackend: BreakPresentationBackend {
    private var previousOptions: NSApplication.PresentationOptions?
    private var strict = false
    func setStrictMode(_ strict: Bool) { self.strict = strict }
    var displays: [DisplayDescriptor] { DisplayTopology.current() }
    func begin() {
        guard previousOptions == nil else { return }
        previousOptions = NSApp.presentationOptions
        // Public process-switch restriction discourages Cmd-Tab in strict mode.
        // Force Quit and session termination remain enabled; no input hooks.
        NSApp.presentationOptions = Self.options(strict: strict)
        NSApp.activate(ignoringOtherApps: true)
    }
    static func options(strict: Bool) -> NSApplication.PresentationOptions {
        strict ? [.autoHideDock, .autoHideMenuBar, .disableProcessSwitching] : [.autoHideDock, .autoHideMenuBar]
    }
    func end() {
        if let previousOptions { NSApp.presentationOptions = previousOptions }
        previousOptions = nil
    }
    func makeCover(display: DisplayDescriptor, runtime: RuntimeState,
                   onEvent: @escaping (EngineEvent) -> Void) throws -> any BreakCover {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.id
        }) else { throw BreakWindowController.PresentationError.missingScreen }
        return AppKitBreakCover(screen: screen, runtime: runtime, onEvent: onEvent)
    }
}

private final class CoverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
@MainActor private final class AppKitBreakCover: BreakCover {
    private let window: NSWindow
    private let model: BreakViewModel
    init(screen: NSScreen, runtime: RuntimeState, onEvent: @escaping (EngineEvent) -> Void) {
        model = BreakViewModel(runtime: runtime)
        window = CoverWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        window.isReleasedWhenClosed = false
        // Cover ordinary application windows while leaving higher system/modal
        // surfaces available. Enforcement is explicitly best effort, not kiosk.
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = false
        window.isMovable = false
        window.backgroundColor = .black
        window.contentView = NSHostingView(rootView: BreakView(model: model, onEvent: onEvent))
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
    }
    func configure(message: String, reduceVisualStimulation: Bool) { model.message = message; model.reduceVisualStimulation = reduceVisualStimulation }
    func update(runtime: RuntimeState) { model.runtime = runtime }
    func setBackground(_ image: CGImage?) { model.image = image }
    func release() { window.orderOut(nil); window.close() }
}
