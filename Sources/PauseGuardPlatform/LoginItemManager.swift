import Foundation
import Darwin

public struct LoginItemOperationError: LocalizedError, Sendable {
    public let operationError: String
    public let cleanupErrors: [String]
    public let remainingPaths: [String]
    public var errorDescription: String? {
        ([operationError] + cleanupErrors + (remainingPaths.isEmpty ? [] : ["仍需移除的登录组件：" + remainingPaths.joined(separator: "、")])).joined(separator: "\n")
    }
}

public struct LoginItemManager {
    public static let label = "com.pauseguard.agent"
    public let homeDirectory: URL
    private let runLaunchctl: ([String]) throws -> Void
    private let removeFile: (URL) throws -> Void
    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                runLaunchctl: @escaping ([String]) throws -> Void = LoginItemManager.launchctl,
                removeFile: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.homeDirectory = homeDirectory
        self.runLaunchctl = runLaunchctl
        self.removeFile = removeFile
    }
    public var plistURL: URL { homeDirectory.appendingPathComponent("Library/LaunchAgents/\(Self.label).plist") }
    public var loginPlistURL: URL { homeDirectory.appendingPathComponent("Library/LaunchAgents/com.pauseguard.login.plist") }
    public var remainingPaths: [String] {
        [plistURL, loginPlistURL].filter { (try? FileManager.default.attributesOfItem(atPath: $0.path)) != nil }.map(\.path)
    }
    public func plistData(appURL: URL, loginStarter: Bool = false) throws -> Data {
        guard appURL.isFileURL, appURL.pathExtension == "app", appURL.path.hasPrefix("/"),
              !appURL.path.contains("\n") else { throw CocoaError(.fileReadInvalidFileName) }
        let plist: [String: Any] = [
            "Label": loginStarter ? "com.pauseguard.login" : Self.label,
            "ProgramArguments": loginStarter ? ["/usr/bin/open", "-g", appURL.path] : [appURL.appendingPathComponent("Contents/MacOS/PauseGuardAgent").path, "--app", appURL.path],
            "RunAtLoad": true,
            "KeepAlive": !loginStarter,
            "ThrottleInterval": 30,
            "ProcessType": "Background"
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
    /// Call only from an explicit user action. Tests substitute only launchctl, never install in the real home.
    public func setEnabled(_ enabled: Bool, appURL: URL) throws {
        let domain = "gui/\(getuid())"
        let jobs = [(Self.label, plistURL), ("com.pauseguard.login", loginPlistURL)]
        if enabled {
            let data = try plistData(appURL: appURL)
            let loginData = try plistData(appURL: appURL, loginStarter: true)
            guard FileManager.default.isExecutableFile(atPath: appURL.appendingPathComponent("Contents/MacOS/PauseGuardAgent").path) else {
                throw CocoaError(.executableNotLoadable)
            }
            guard jobs.allSatisfy({ !FileManager.default.fileExists(atPath: $0.1.path) }) else { throw CocoaError(.fileWriteFileExists) }
            var written: [URL] = []
            var loaded: [String] = []
            do {
                try PrivateFiles.write(data, to: plistURL); written.append(plistURL)
                try PrivateFiles.write(loginData, to: loginPlistURL); written.append(loginPlistURL)
                for (label, url) in jobs {
                    try runLaunchctl(["bootstrap", domain, url.path]); loaded.append(label)
                }
                try AgentHistoryStore(directory: homeDirectory.appendingPathComponent("Library/Application Support/PauseGuard")).resetAfterExplicitEnable()
            } catch {
                // Preserve any job whose rollback fails so users can retry disabling it.
                var retained = Set<String>()
                var cleanupErrors: [String] = []
                for label in loaded.reversed() {
                    do { try runLaunchctl(["bootout", domain + "/" + label]) }
                    catch { retained.insert(label); cleanupErrors.append(error.localizedDescription) }
                }
                for url in written where !retained.contains(url.deletingPathExtension().lastPathComponent) {
                    do { try removeFile(url) }
                    catch { cleanupErrors.append(url.path + ": " + error.localizedDescription) }
                }
                throw LoginItemOperationError(operationError: error.localizedDescription, cleanupErrors: cleanupErrors, remainingPaths: remainingPaths)
            }
        } else {
            var errors: [String] = []
            for (label, url) in jobs where FileManager.default.fileExists(atPath: url.path) {
                do {
                    do { try runLaunchctl(["bootout", domain + "/" + label]) }
                    catch {
                        // launchctl ESRCH: an installed one-shot job may already be unloaded.
                        let ns = error as NSError
                        guard ns.domain == "PauseGuard.LoginItem", ns.code == 3 else { throw error }
                    }
                    try removeFile(url)
                } catch { errors.append(url.path + ": " + error.localizedDescription) }
            }
            if let first = errors.first { throw LoginItemOperationError(operationError: first, cleanupErrors: Array(errors.dropFirst()), remainingPaths: remainingPaths) }
        }
    }

    public static func launchctl(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let output = Pipe(); process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "PauseGuard.LoginItem", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "登录启动设置失败：" + (String(data: data, encoding: .utf8) ?? "launchctl error")])
        }
    }
}
