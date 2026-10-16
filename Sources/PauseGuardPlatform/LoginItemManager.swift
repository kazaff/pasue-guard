import Foundation
import Darwin

public struct LoginItemManager {
    public static let label = "com.pauseguard.agent"
    public let homeDirectory: URL
    private let runLaunchctl: ([String]) throws -> Void
    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                runLaunchctl: @escaping ([String]) throws -> Void = LoginItemManager.launchctl) {
        self.homeDirectory = homeDirectory
        self.runLaunchctl = runLaunchctl
    }
    public var plistURL: URL { homeDirectory.appendingPathComponent("Library/LaunchAgents/\(Self.label).plist") }
    public var loginPlistURL: URL { homeDirectory.appendingPathComponent("Library/LaunchAgents/com.pauseguard.login.plist") }
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
            } catch {
                // Preserve any job whose rollback fails so users can retry disabling it.
                var retained = Set<String>()
                for label in loaded.reversed() {
                    do { try runLaunchctl(["bootout", domain + "/" + label]) }
                    catch { retained.insert(label) }
                }
                for url in written where !retained.contains(url.deletingPathExtension().lastPathComponent) {
                    try? FileManager.default.removeItem(at: url)
                }
                throw error
            }
        } else {
            var firstError: (any Error)?
            for (label, url) in jobs where FileManager.default.fileExists(atPath: url.path) {
                do {
                    do { try runLaunchctl(["bootout", domain + "/" + label]) }
                    catch {
                        // launchctl ESRCH: an installed one-shot job may already be unloaded.
                        let ns = error as NSError
                        guard ns.domain == "PauseGuard.LoginItem", ns.code == 3 else { throw error }
                    }
                    try FileManager.default.removeItem(at: url)
                } catch { if firstError == nil { firstError = error } }
            }
            if let firstError { throw firstError }
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
