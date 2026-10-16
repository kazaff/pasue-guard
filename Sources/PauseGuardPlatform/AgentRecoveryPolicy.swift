import Foundation

public enum AgentDecision: Equatable, Sendable { case none, relaunch, stopRetrying }

/// Agent-only state. Never writes the app coordinator's session snapshot.
public struct AgentRecoveryPolicy: Codable, Sendable {
    public private(set) var attempts: [Date] = []
    private var blocked = false
    public init() {}
    static var corrupt: Self { var policy = Self(); policy.blocked = true; return policy }
    public mutating func decision(session: PersistedSession?, appRunning: Bool, now: Date) -> AgentDecision {
        guard let session, session.isValid, session.desiredRunning, !appRunning else { return .none }
        guard !blocked, now.timeIntervalSince1970.isFinite,
              attempts.allSatisfy({ $0.timeIntervalSince1970.isFinite }) else { return .stopRetrying }
        // Future timestamps stay charged after a backward wall-clock adjustment.
        attempts.removeAll { now.timeIntervalSince($0) >= 300 }
        guard attempts.count < 3 else { return .stopRetrying }
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
        try PrivateFiles.write(JSONEncoder().encode(policy), to: url)
    }
}
