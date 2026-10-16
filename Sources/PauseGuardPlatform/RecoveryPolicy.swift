import Foundation
import PauseGuardCore

public enum RecoveryPolicy {
    public static func restore(_ session: PersistedSession, now: ClockSnapshot, currentSettings: UserSettings? = nil, availability: Availability? = nil) -> RuntimeState {
        guard session.isValid, now.isValid else { return RuntimeState() }
        if !session.desiredRunning {
            var stopped = RuntimeState(settings: currentSettings ?? session.runtime.cycleSettings)
            stopped.skippedBreakCount = session.runtime.skippedBreakCount
            return stopped
        }
        var state = session.runtime
        let sameBoot = session.clock.bootID == now.bootID && now.continuousUptime >= session.clock.continuousUptime
        let elapsed = sameBoot ? now.continuousUptime - session.clock.continuousUptime : 0
        if !sameBoot {
            state.sleeping = false
            state.locked = false
            state.awayStartedAt = nil
            state.awayElapsedSeconds = 0
        } else if !state.isAvailable, let started = state.awayStartedAt {
            guard started <= session.clock.continuousUptime else { return RuntimeState() }
            state.awayElapsedSeconds = now.continuousUptime - started
        }
        if let availability {
            if availability.isAvailable, !state.isAvailable {
                // Let the engine own the full-away-rest return transition.
                var returning = TimerEngine(restoring: state, settings: currentSettings ?? state.cycleSettings, at: now.continuousUptime)
                returning.handle(.availabilityChanged(sleeping: false, locked: false), at: now.continuousUptime)
                state = returning.state
            } else {
                if state.isAvailable && !availability.isAvailable {
                    state.awayStartedAt = now.continuousUptime
                    state.awayElapsedSeconds = 0
                }
                state.sleeping = availability.sleeping
                state.locked = availability.locked
            }
        }
        if state.phase == .breaking {
            state.breakRemainingSeconds = max(0, state.breakRemainingSeconds - elapsed)
            if state.breakRemainingSeconds == 0, state.isAvailable {
                state.phase = .working
                state.skippedBreakCount = 0
                state.cycleSettings = (currentSettings ?? state.cycleSettings).validated()
                state.workRemainingSeconds = state.cycleSettings.workDurationSeconds
                state.breakRemainingSeconds = state.cycleSettings.breakDurationSeconds
                state.cycleNumber += 1
                state.lastTransitionReason = .breakCompleted
            }
        }
        // Work is never charged while the app was absent, and paused phases stay paused.
        return state
    }
}
