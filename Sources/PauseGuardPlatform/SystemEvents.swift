import AppKit
import CoreGraphics

public struct Availability: Equatable, Sendable {
    public var sleeping: Bool
    public var locked: Bool
    public init(sleeping: Bool = false, locked: Bool = true) {
        self.sleeping = sleeping
        self.locked = locked
    }
    public var isAvailable: Bool { !sleeping && !locked }
}

public enum AvailabilityEvent: Sendable {
    case sleep, wake, locked, unlocked, sessionActive, sessionInactive
}

/// Independent causes form a union; waking or switching in cannot clear a lock.
public struct AvailabilityReducer: Sendable {
    private var sleeping: Bool
    private var screenLocked: Bool
    private var sessionInactive = false
    public init(initial: Availability = Availability()) {
        sleeping = initial.sleeping
        screenLocked = initial.locked
    }
    public var availability: Availability {
        Availability(sleeping: sleeping, locked: screenLocked || sessionInactive)
    }
    @discardableResult public mutating func update(_ event: AvailabilityEvent) -> Availability {
        switch event {
        case .sleep: sleeping = true
        case .wake: sleeping = false
        case .locked: screenLocked = true
        case .unlocked: screenLocked = false
        case .sessionActive: sessionInactive = false
        case .sessionInactive: sessionInactive = true
        }
        return availability
    }
}

@MainActor public protocol SystemEventSource: AnyObject {
    var currentAvailability: Availability { get }
    func start(onAvailability: @escaping @MainActor (Availability) -> Void)
    func stop()
}

/// macOS 14+: workspace sleep/session notifications are public APIs. The
/// com.apple.screenIsLocked/Unlocked distributed notifications and session lock
/// dictionary entry are best-effort OS conventions, not public lock contracts.
/// Missing/unreadable lock evidence is unavailable, never assumed unlocked.
@MainActor public final class SystemEvents: SystemEventSource {
    private var reducer = AvailabilityReducer()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var callback: (@MainActor (Availability) -> Void)?
    public init() {}
    public var currentAvailability: Availability { sampleReducer().availability }
    private func sampleReducer() -> AvailabilityReducer {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any],
              let onConsole = info[kCGSessionOnConsoleKey as String] as? Bool,
              let locked = info["CGSSessionScreenIsLocked"] as? Bool else { return AvailabilityReducer() }
        var sample = AvailabilityReducer(initial: Availability(sleeping: false, locked: locked))
        if !onConsole { sample.update(.sessionInactive) }
        return sample
    }
    public func start(onAvailability: @escaping @MainActor (Availability) -> Void) {
        stop()
        callback = onAvailability
        reducer = sampleReducer()
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification, .sleep)
        observe(workspace, NSWorkspace.didWakeNotification, .wake)
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionActive)
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionInactive)
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked"), .locked)
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked"), .unlocked)
        onAvailability(reducer.availability)
    }
    public func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        callback = nil
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ event: AvailabilityEvent) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.callback?(self.reducer.update(event))
            }
        }
        observers.append((center, token))
    }
}
