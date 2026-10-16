import Combine
import Foundation
import PauseGuardCore
import PauseGuardPlatform

/// Owns all engine mutations and serialized persistence on the main actor.
/// UI observes runtime; creating this coordinator never creates strict covers.
@MainActor public final class AppController: ObservableObject {
    @Published public private(set) var settings: UserSettings
    @Published public private(set) var runtime: RuntimeState
    @Published public private(set) var lastError: String?
    public private(set) var desiredRunning: Bool
    private var engine: TimerEngine
    private let store: StateStore
    private let eventLog: EventLog
    private let clock: @MainActor () -> ClockSnapshot
    private let idleSeconds: @MainActor () -> TimeInterval
    private let systemEvents: any SystemEventSource
    private var timer: Timer?
    private var lastSaveUptime: TimeInterval
    private var terminated = false

    public init(store: StateStore = StateStore(),
                clock: @escaping @MainActor () -> ClockSnapshot = { SystemClock.snapshot() },
                idleSeconds: @escaping @MainActor () -> TimeInterval = { ActivityMonitor().idleSeconds() },
                systemEvents: (any SystemEventSource)? = nil,
                startTimer: Bool = true) {
        self.store = store
        self.eventLog = EventLog(directory: store.directory)
        self.clock = clock
        self.idleSeconds = idleSeconds
        let source = systemEvents ?? SystemEvents()
        self.systemEvents = source
        let loaded = store.loadSettings()
        settings = loaded
        let now = clock()
        // Capture current availability before recovery can complete any break.
        let availability = source.currentAvailability
        if let saved = store.loadSession() {
            let recovered = RecoveryPolicy.restore(saved, now: now, currentSettings: loaded, availability: availability)
            engine = TimerEngine(restoring: recovered, settings: loaded, at: now.continuousUptime)
            desiredRunning = saved.desiredRunning && recovered.phase != .stopped
        } else {
            engine = TimerEngine(settings: loaded)
            desiredRunning = false
        }
        engine.handle(.availabilityChanged(sleeping: availability.sleeping, locked: availability.locked), at: now.continuousUptime)
        runtime = engine.state
        lastSaveUptime = now.continuousUptime
        persist(at: now)
        source.start { [weak self] value in
            self?.send(.availabilityChanged(sleeping: value.sleeping, locked: value.locked))
        }
        if startTimer {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.send(.tick(idleSeconds: self.idleSeconds()))
                }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    public func send(_ event: EngineEvent) {
        guard !terminated else { return }
        if case .updateSettings(let value) = event { updateSettings(value); return }
        let now = clock()
        let previous = runtime
        // Age time before checking action permissions: an event arriving at
        // work expiry must not stop the break entered at that same boundary.
        switch event {
        case .stop, .pause:
            engine.handle(.tick(idleSeconds: idleSeconds()), at: now.continuousUptime)
            if engine.state.phase != .breaking { engine.handle(event, at: now.continuousUptime) }
        default:
            engine.handle(event, at: now.continuousUptime)
        }
        runtime = engine.state
        desiredRunning = runtime.phase != .stopped
        let availabilityChanged = previous.sleeping != runtime.sleeping || previous.locked != runtime.locked
        if previous.phase != runtime.phase || previous.cycleNumber != runtime.cycleNumber || availabilityChanged || now.continuousUptime - lastSaveUptime >= 5 {
            persist(at: now)
        }
        if previous.phase != runtime.phase {
            eventLog.append(kind: "phase", detail: "\(previous.phase.rawValue) -> \(runtime.phase.rawValue): \(runtime.lastTransitionReason.rawValue)")
        }
    }

    public func updateSettings(_ value: UserSettings) {
        guard !terminated else { return }
        settings = value.validated()
        let now = clock()
        engine.handle(.updateSettings(settings), at: now.continuousUptime)
        runtime = engine.state
        do { try store.saveSettings(settings) } catch { record(error) }
        persist(at: now)
    }

    /// Normal menu/window quit must consult this gate before terminating.
    /// applicationWillTerminate still calls shutdown for forced/system exits.
    @discardableResult public func requestQuit() -> Bool {
        guard !terminated else { return true }
        send(.tick(idleSeconds: idleSeconds()))
        guard runtime.phase != .breaking else { return false }
        shutdown()
        return true
    }

    /// Called by applicationWillTerminate. Save the stopped intent before
    /// removing observers/timers, so the supervisor cannot restart a user quit.
    public func shutdown() {
        guard !terminated else { return }
        desiredRunning = false
        persist(at: clock())
        terminated = true
        timer?.invalidate()
        timer = nil
        systemEvents.stop()
    }

    private func persist(at now: ClockSnapshot) {
        do {
            try store.saveSession(PersistedSession(runtime: runtime, clock: now, desiredRunning: desiredRunning))
            lastSaveUptime = now.continuousUptime
        } catch { record(error) }
    }
    private func record(_ error: Error) {
        lastError = error.localizedDescription
        eventLog.append(kind: "error", detail: error.localizedDescription)
    }
}
