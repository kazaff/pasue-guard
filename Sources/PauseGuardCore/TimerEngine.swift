import Foundation

public enum EngineEvent: Equatable, Sendable {
    case start, pause, resume, stop
    case tick(idleSeconds: TimeInterval)
    case beginBreak, endBreak, emergencyRelease
    /// The platform reducer supplies the full current availability snapshot.
    case availabilityChanged(sleeping: Bool, locked: Bool)
    case updateSettings(UserSettings)
}

/// Pure value state machine. Times must use one continuous monotonic clock,
/// including sleep. A tick's idle sample describes inactivity ending at that tick.
public struct TimerEngine: Sendable {
    public private(set) var state: RuntimeState
    private var settings: UserSettings
    private var lastUptime: TimeInterval?
    private var lastIdleSeconds: TimeInterval = 0

    public init(settings: UserSettings) {
        self.settings = settings.validated()
        state = RuntimeState(settings: settings.validated())
    }

    public mutating func handle(_ event: EngineEvent, at uptime: TimeInterval) {
        // Ignore stale events entirely; never move the clock baseline backwards.
        guard uptime.isFinite, uptime >= 0, uptime >= (lastUptime ?? 0) else { return }
        let delta = uptime - (lastUptime ?? uptime)
        lastUptime = uptime
        if case .tick(let idle) = event {
            lastIdleSeconds = idle.isFinite ? max(0, idle) : .infinity
        }
        advance(by: delta, at: uptime)
        switch event {
        case .start:
            guard state.phase == .stopped else { return }
            startWork(reason: .started)
        case .beginBreak:
            guard isWorking else { return }
            startBreak(reason: .earlyBreak)
        case .endBreak:
            guard state.phase == .breaking, state.isAvailable,
                  !state.cycleSettings.strictMode else { return }
            startWork(reason: .breakEnded)
        case .emergencyRelease:
            guard state.phase != .stopped, state.phase != .paused else { return }
            pause(reason: .emergencyRelease)
        case .pause:
            guard isWorking else { return }
            pause(reason: .userPaused)
        case .resume:
            guard state.phase == .paused else { return }
            state.phase = state.pausedPhase ?? .working
            state.pausedPhase = nil
            state.lastTransitionReason = .resumed
            resetAwayInterval()
        case .stop:
            state.phase = .stopped
            state.pausedPhase = nil
            state.awayStartedAt = nil
            state.awayElapsedSeconds = 0
            state.lastTransitionReason = .stopped
        case .updateSettings(let newSettings): settings = newSettings.validated()
        case .availabilityChanged(let sleeping, let locked):
            updateAvailability(sleeping: sleeping, locked: locked, at: uptime)
        case .tick: break
        }
    }

    private var isWorking: Bool { state.phase == .working || state.phase == .preparing }

    private mutating func advance(by delta: TimeInterval, at uptime: TimeInterval) {
        if !state.isAvailable, let awayStart = state.awayStartedAt {
            state.awayElapsedSeconds = uptime - awayStart
        }
        if isWorking {
            guard state.isAvailable else { return }
            let counted: TimeInterval
            if state.cycleSettings.timerMode == .active {
                // Only the interval before the idle threshold is credited. This
                // also handles sparse ticks crossing the 60-second boundary.
                counted = max(0, delta - max(0, lastIdleSeconds - UserSettings.idleThresholdSeconds))
            } else {
                counted = delta
            }
            let oldRemaining = state.workRemainingSeconds
            state.workRemainingSeconds = max(0, oldRemaining - counted)
            if state.workRemainingSeconds == 0 {
                startBreak(reason: .workCompleted)
                // Work expiry happened within this interval; elapsed real time
                // since that boundary is already part of the current break.
                let elapsedBreak = max(0, delta - oldRemaining)
                state.breakRemainingSeconds = max(0, state.cycleSettings.breakDurationSeconds - elapsedBreak)
                if state.breakRemainingSeconds == 0 { startWork(reason: .breakCompleted) }
            } else if state.cycleSettings.preBreakWarningSeconds > 0,
                      state.workRemainingSeconds <= state.cycleSettings.preBreakWarningSeconds,
                      state.phase != .preparing {
                state.phase = .preparing
                state.lastTransitionReason = .preBreakWarning
            }
        } else if state.phase == .breaking {
            state.breakRemainingSeconds = max(0, state.breakRemainingSeconds - delta)
            if state.breakRemainingSeconds == 0, state.isAvailable {
                startWork(reason: .breakCompleted)
            }
        }
    }

    private mutating func updateAvailability(sleeping: Bool, locked: Bool, at uptime: TimeInterval) {
        let wasAvailable = state.isAvailable
        state.sleeping = sleeping
        state.locked = locked
        if wasAvailable && !state.isAvailable {
            state.awayStartedAt = uptime
            state.awayElapsedSeconds = 0
        } else if !wasAvailable && state.isAvailable {
            if isWorking, state.awayElapsedSeconds >= state.cycleSettings.breakDurationSeconds {
                startWork(reason: .awayRestCompleted)
            } else if state.phase == .breaking, state.breakRemainingSeconds == 0 {
                startWork(reason: .breakCompleted)
            }
            state.awayStartedAt = nil
            state.awayElapsedSeconds = 0
        }
    }

    private mutating func pause(reason: TransitionReason) {
        state.pausedPhase = state.phase
        state.phase = .paused
        state.lastTransitionReason = reason
        state.awayStartedAt = nil
        state.awayElapsedSeconds = 0
    }

    private mutating func resetAwayInterval() {
        state.awayStartedAt = state.isAvailable ? nil : lastUptime
        state.awayElapsedSeconds = 0
    }

    private mutating func startBreak(reason: TransitionReason) {
        // Work fields remain frozen for the work cycle; the next corresponding
        // break captures the latest duration and enforcement settings.
        state.cycleSettings.breakDurationSeconds = settings.breakDurationSeconds
        state.cycleSettings.strictMode = settings.strictMode
        state.breakRemainingSeconds = settings.breakDurationSeconds
        state.phase = .breaking
        state.lastTransitionReason = reason
    }

    private mutating func startWork(reason: TransitionReason) {
        state.cycleSettings = settings
        state.workRemainingSeconds = settings.workDurationSeconds
        state.breakRemainingSeconds = settings.breakDurationSeconds
        state.cycleNumber += 1
        state.phase = .working
        state.lastTransitionReason = reason
        resetAwayInterval()
    }
}
