import Foundation

public enum TimerMode: String, Codable, Sendable {
    case elapsed, active
}

public struct UserSettings: Codable, Equatable, Sendable {
    public var workDurationSeconds: TimeInterval
    public var breakDurationSeconds: TimeInterval
    public var timerMode: TimerMode
    public var strictMode: Bool
    public var preBreakWarningSeconds: TimeInterval
    public static let idleThresholdSeconds: TimeInterval = 60

    public init(workDurationSeconds: TimeInterval = 2700,
                breakDurationSeconds: TimeInterval = 300,
                timerMode: TimerMode = .elapsed,
                strictMode: Bool = true,
                preBreakWarningSeconds: TimeInterval = 0) {
        self.workDurationSeconds = Self.bounded(workDurationSeconds, to: 300...10800, fallback: 2700)
        self.breakDurationSeconds = Self.bounded(breakDurationSeconds, to: 60...3600, fallback: 300)
        self.timerMode = timerMode
        self.strictMode = strictMode
        self.preBreakWarningSeconds = Self.bounded(preBreakWarningSeconds, to: 0...60, fallback: 0)
    }

    /// Revalidate settings after callers edit the public configuration fields.
    public func validated() -> UserSettings {
        UserSettings(workDurationSeconds: workDurationSeconds,
                     breakDurationSeconds: breakDurationSeconds,
                     timerMode: timerMode, strictMode: strictMode,
                     preBreakWarningSeconds: preBreakWarningSeconds)
    }

    private static func bounded(_ value: TimeInterval, to range: ClosedRange<TimeInterval>,
                                fallback: TimeInterval) -> TimeInterval {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}
