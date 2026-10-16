import Foundation

public enum RuntimePhase: String, Codable, Sendable {
    case stopped, working, preparing, breaking, recovering, paused, error
}

public enum TransitionReason: String, Codable, Sendable {
    case initialized, started, workCompleted, breakCompleted, earlyBreak, breakEnded
    case userPaused, resumed, stopped, emergencyRelease, awayRestCompleted, preBreakWarning, warningSkipped
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
    private var deferredBreakCount: Int?
    public var skippedBreakCount: Int {
        get { deferredBreakCount ?? 0 }
        set { deferredBreakCount = newValue }
    }
    public func pendingBreakDuration(base: TimeInterval) -> TimeInterval {
        min(3600, base * pow(2, Double(min(6, max(0, skippedBreakCount)))))
    }
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
        let validPausedPhase = pausedPhase.map { [.working, .preparing, .breaking].contains($0) } ?? false
        return settings == settings.validated() &&
            workRemainingSeconds.isFinite && (0...settings.workDurationSeconds).contains(workRemainingSeconds) &&
            breakRemainingSeconds.isFinite && (0...settings.breakDurationSeconds).contains(breakRemainingSeconds) &&
            (0...6).contains(skippedBreakCount) &&
            cycleNumber >= 0 && cycleNumber < Int.max &&
            awayElapsedSeconds.isFinite && awayElapsedSeconds >= 0 &&
            (awayStartedAt.map { $0.isFinite && $0 >= 0 } ?? true) &&
            (phase == .paused ? validPausedPhase : pausedPhase == nil)
    }
}
