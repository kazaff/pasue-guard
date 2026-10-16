import CoreGraphics
import Foundation

/// Reads aggregate HID inactivity only. No event tap, key data or input history.
public struct ActivityMonitor: Sendable {
    public init() {}
    public func idleSeconds() -> TimeInterval {
        // SDK kCGAnyInputEventType is the all-bits-set CGEventType sentinel.
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        return seconds.isFinite && seconds >= 0 ? seconds : .infinity
    }
}
