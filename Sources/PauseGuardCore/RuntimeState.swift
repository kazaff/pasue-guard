import Foundation

public enum RuntimePhase: String, Codable, Sendable {
    case stopped, working, preparing, breaking, recovering, paused, error
}

public enum TransitionReason: String, Codable, Sendable {
    case initialized, started, workCompleted, breakCompleted, earlyBreak, breakEnded
    case userPaused, resumed, stopped, emergencyRelease, awayRestCompleted, preBreakWarning
}

public struct RuntimeState: Codable, Equatable, Sendable {
    public var phase: RuntimePhase
    public var workRemainingSeconds: TimeInterval
    public var breakRemainingSeconds: TimeInterval
    public var cycleNumber: Int
    public var lastTransitionReason: TransitionReason
    public var cycleSettings: UserSettings
    public var sleeping: Bool = false
    public var locked: Bool = false
    public var awayStartedAt: TimeInterval?
    public var awayElapsedSeconds: TimeInterval = 0
    public var pausedPhase: RuntimePhase?
    public var isAvailable: Bool { !sleeping && !locked }

    public init(settings: UserSettings = UserSettings()) {
        phase = .stopped
        workRemainingSeconds = settings.workDurationSeconds
        breakRemainingSeconds = settings.breakDurationSeconds
        cycleNumber = 0
        lastTransitionReason = .initialized
        cycleSettings = settings
    }
}

extension RuntimeState {
    /// Reject malformed persisted state before it can drive enforcement or arithmetic.
    public var isValidForRestore: Bool {
        let settings = cycleSettings
        return settings == settings.validated() &&
            workRemainingSeconds.isFinite && (0...settings.workDurationSeconds).contains(workRemainingSeconds) &&
            breakRemainingSeconds.isFinite && (0...settings.breakDurationSeconds).contains(breakRemainingSeconds) &&
            cycleNumber >= 0 && cycleNumber < Int.max &&
            awayElapsedSeconds.isFinite && awayElapsedSeconds >= 0 &&
            (awayStartedAt.map { $0.isFinite && $0 >= 0 } ?? true) &&
            (pausedPhase == nil || [.working, .preparing, .breaking].contains(pausedPhase!)) &&
            (phase == .paused || pausedPhase == nil)
    }
}
