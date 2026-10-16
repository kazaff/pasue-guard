import Foundation
import Darwin
import PauseGuardCore

public struct PersistedSession: Codable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var runtime: RuntimeState
    public var clock: ClockSnapshot
    public var desiredRunning: Bool
    public var lastHeartbeat: Date
    public var recoveryAttempts: Int

    public init(runtime: RuntimeState, clock: ClockSnapshot, desiredRunning: Bool,
                lastHeartbeat: Date? = nil, recoveryAttempts: Int = 0,
                schemaVersion: Int = currentSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.runtime = runtime
        self.clock = clock
        self.desiredRunning = desiredRunning
        self.lastHeartbeat = lastHeartbeat ?? clock.wallDate
        self.recoveryAttempts = recoveryAttempts
    }
    var isValid: Bool {
        schemaVersion == Self.currentSchemaVersion && runtime.isValidForRestore && clock.isValid &&
        lastHeartbeat.timeIntervalSince1970.isFinite && recoveryAttempts >= 0 &&
        (runtime.awayStartedAt.map { $0 <= clock.continuousUptime } ?? true)
    }
}

private struct PersistedSettings: Codable {
    var schemaVersion = 1
    var settings: UserSettings
}

public enum StateStoreError: Error {
    case invalidSession, unsafePath
}

/// Synchronous local store. Callers serialize writes (the app coordinator owns it).
public struct StateStore: Sendable {
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PauseGuard", isDirectory: true)
    }
    public let directory: URL
    public init(directory: URL = Self.defaultDirectory) { self.directory = directory }

    public func loadSettings() -> UserSettings {
        guard let data = try? PrivateFiles.read(directory.appendingPathComponent("settings.json")),
              let saved = try? JSONDecoder().decode(PersistedSettings.self, from: data),
              saved.schemaVersion == 1 else { return UserSettings() }
        return saved.settings.validated()
    }
    public func saveSettings(_ settings: UserSettings) throws {
        let url = directory.appendingPathComponent("settings.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let saved = (try? PrivateFiles.read(url)).flatMap { try? JSONDecoder().decode(PersistedSettings.self, from: $0) }
            if saved?.schemaVersion != 1 { try PrivateFiles.preserve(url) }
        }
        try PrivateFiles.write(JSONEncoder().encode(PersistedSettings(settings: settings.validated())), to: url)
    }
    public func loadSession() -> PersistedSession? {
        guard let data = try? PrivateFiles.read(directory.appendingPathComponent("session.json")),
              let saved = try? JSONDecoder().decode(PersistedSession.self, from: data), saved.isValid else { return nil }
        return saved
    }
    public func saveSession(_ session: PersistedSession) throws {
        guard session.isValid else { throw StateStoreError.invalidSession }
        let url = directory.appendingPathComponent("session.json")
        if FileManager.default.fileExists(atPath: url.path), loadSession() == nil {
            try PrivateFiles.preserve(url)
        }
        try PrivateFiles.write(JSONEncoder().encode(session), to: url)
    }
}

enum PrivateFiles {
    static func read(_ url: URL) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 1_048_576 else {
            throw StateStoreError.unsafePath
        }
        return try Data(contentsOf: url)
    }
    /// Move untrusted bytes aside only when a caller explicitly saves replacement state.
    /// The move is atomic within the directory; a crash leaves either the original or evidence.
    static func preserve(_ url: URL) throws {
        let fm = FileManager.default
        let attributes = try fm.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw StateStoreError.unsafePath }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let evidence = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".preserved-" + UUID().uuidString)
        try fm.moveItem(at: url, to: evidence)
    }
    static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attrs = try fm.attributesOfItem(atPath: directory.path)
        guard attrs[.type] as? FileAttributeType == .typeDirectory else { throw StateStoreError.unsafePath }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? fm.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        guard rename(temporary.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
