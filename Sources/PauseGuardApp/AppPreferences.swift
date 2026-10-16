import Foundation
import Darwin

public struct AppPreferences: Codable, Equatable, Sendable {
    public var onboardingComplete = false
    public var loginAtLaunch = false
    public var singleImage = false
    public var reduceVisualStimulation = false
    public var customMessages: [String] = []
    public init() {}
    private enum CodingKeys: String, CodingKey { case onboardingComplete, loginAtLaunch, singleImage, reduceVisualStimulation, customMessages }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        onboardingComplete = try values.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
        loginAtLaunch = try values.decodeIfPresent(Bool.self, forKey: .loginAtLaunch) ?? false
        singleImage = try values.decodeIfPresent(Bool.self, forKey: .singleImage) ?? false
        reduceVisualStimulation = try values.decodeIfPresent(Bool.self, forKey: .reduceVisualStimulation) ?? false
        customMessages = try values.decodeIfPresent([String].self, forKey: .customMessages) ?? []
    }
    public func validated() -> Self {
        var copy = self
        copy.customMessages = customMessages.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)) }.filter { !$0.isEmpty }
        return copy
    }
    public func randomMessage() -> String {
        validated().customMessages.randomElement() ?? ["让目光看向远处，放松肩膀，起身活动。", "给眼睛一点留白，给自己一点时间。", "慢慢呼吸，让身体重新舒展。"].randomElement()!
    }
}
public struct PreferencesStore {
    private struct Document: Codable { var schemaVersion = 1; var preferences: AppPreferences }
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    private var url: URL { directory.appendingPathComponent("preferences.json") }
    public func load() -> AppPreferences {
        guard let document = read(), document.schemaVersion == 1 else { return AppPreferences() }
        return document.preferences.validated()
    }
    private func read() -> Document? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.size] as? NSNumber)?.intValue ?? Int.max < 1_048_576,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Document.self, from: data)
    }
    public func save(_ value: AppPreferences) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if fm.fileExists(atPath: url.path), read()?.schemaVersion != 1 {
            let attrs = try fm.attributesOfItem(atPath: url.path)
            guard attrs[.type] as? FileAttributeType == .typeRegular else { throw CocoaError(.fileWriteInvalidFileName) }
            try fm.moveItem(at: url, to: directory.appendingPathComponent("preferences.json.preserved-" + UUID().uuidString))
        }
        let temporary = directory.appendingPathComponent("." + UUID().uuidString + ".tmp")
        guard fm.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? fm.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.write(contentsOf: JSONEncoder().encode(Document(preferences: value.validated())))
            try handle.synchronize(); try handle.close()
        } catch { try? handle.close(); throw error }
        guard rename(temporary.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
