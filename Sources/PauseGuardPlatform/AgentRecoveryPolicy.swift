import Foundation
import Darwin

public enum AgentDecision: Equatable, Sendable { case none, relaunch, stopRetrying }

/// Agent-only state. Never writes the app coordinator's session snapshot.
public struct AgentRecoveryPolicy: Codable, Equatable, Sendable {
    public private(set) var attempts: [Date] = []
    private var blocked = false
    private let schemaVersion = 2
    private enum CodingKeys: String, CodingKey { case schemaVersion, attempts, blocked }
    public init() {}
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == 2 else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values, debugDescription: "Unsupported guardian history; explicitly reenable to reset")
        }
        attempts = try values.decode([Date].self, forKey: .attempts)
        blocked = try values.decode(Bool.self, forKey: .blocked)
        guard attempts.count <= 3, attempts.allSatisfy({ $0.timeIntervalSince1970.isFinite }) else {
            throw DecodingError.dataCorruptedError(forKey: .attempts, in: values, debugDescription: "Invalid guardian history")
        }
    }
    static var corrupt: Self { var policy = Self(); policy.blocked = true; return policy }
    public mutating func decision(session: PersistedSession?, appRunning: Bool, now: Date) -> AgentDecision {
        guard let session, session.isValid, session.desiredRunning, !appRunning else { return .none }
        guard !blocked, now.timeIntervalSince1970.isFinite,
              attempts.allSatisfy({ $0.timeIntervalSince1970.isFinite }), attempts.count < 3 else {
            blocked = true
            return .stopRetrying
        }
        // Attempts never expire: a brief live PID or clock change is not proof of recovery.
        // Only successful explicit guardian reenable resets this budget.
        attempts.append(now)
        return .relaunch
    }
}

public struct AgentHistoryStore {
    public let directory: URL
    public init(directory: URL = StateStore.defaultDirectory) { self.directory = directory }
    private var url: URL { directory.appendingPathComponent("agent-history.json") }
    public func load() -> AgentRecoveryPolicy {
        guard FileManager.default.fileExists(atPath: url.path) else { return AgentRecoveryPolicy() }
        guard let data = try? PrivateFiles.read(url),
              let policy = try? JSONDecoder().decode(AgentRecoveryPolicy.self, from: data) else { return .corrupt }
        return policy
    }
    public func save(_ policy: AgentRecoveryPolicy) throws {
        if FileManager.default.fileExists(atPath: url.path),
           (try? JSONDecoder().decode(AgentRecoveryPolicy.self, from: PrivateFiles.read(url))) == nil {
            try PrivateFiles.preserve(url)
        }
        try PrivateFiles.write(JSONEncoder().encode(policy), to: url)
    }
    /// Agent polling transaction: reload explicit resets and durably charge all transitions before launch.
    public func decision(session: PersistedSession?, appRunning: Bool, now: Date) throws -> AgentDecision {
        try withLock {
            var policy = load()
            let previous = policy
            let decision = policy.decision(session: session, appRunning: appRunning, now: now)
            if policy != previous { try save(policy) }
            return decision
        }
    }
    /// Called only after both jobs were successfully installed by an explicit user action.
    public func resetAfterExplicitEnable() throws {
        try withLock { try save(AgentRecoveryPolicy()) }
    }
    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = open(directory.appendingPathComponent("agent-history.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}
