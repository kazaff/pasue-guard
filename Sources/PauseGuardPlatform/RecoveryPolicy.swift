import Foundation
import PauseGuardCore

public enum RecoveryPolicy {
    public static func restore(_ session: PersistedSession, now: ClockSnapshot) -> RuntimeState {
        guard session.isValid, now.isValid, session.desiredRunning else { return RuntimeState() }
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
        if state.phase == .breaking {
            state.breakRemainingSeconds = max(0, state.breakRemainingSeconds - elapsed)
            if state.breakRemainingSeconds == 0, state.isAvailable {
                state.phase = .working
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
