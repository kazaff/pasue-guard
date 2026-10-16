import AppKit
import Foundation
import Darwin
import PauseGuardPlatform

@main struct PauseGuardAgent {
    @MainActor static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--help"] {
            print("PauseGuardAgent [--install | --uninstall | --print-plist | --print-login-plist] --app /absolute/PauseGuard.app")
            return
        }
        // Demo must never touch LaunchAgents or production state, even when combined with other flags.
        guard !args.contains("--demo") else { fail("Agent is unavailable in demo mode.") }
        let mode: String?
        if ["--install", "--uninstall", "--print-plist", "--print-login-plist"].contains(args.first ?? "") { mode = args.first } else { mode = nil }
        let rest = mode == nil ? args : Array(args.dropFirst())
        guard rest.count == 2, rest[0] == "--app", rest[1].hasPrefix("/") else { fail("Expected --app /absolute/PauseGuard.app") }
        let app = URL(fileURLWithPath: rest[1]).standardizedFileURL.resolvingSymlinksInPath()
        let agent = app.appendingPathComponent("Contents/MacOS/PauseGuardAgent")
        let own = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        guard app.pathExtension == "app", own == agent,
              Bundle(url: app)?.bundleIdentifier == "com.pauseguard.app",
              FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/PauseGuard").path) else {
            fail("Run the agent inside a valid PauseGuard.app bundle.")
        }
        if mode == "--print-plist" || mode == "--print-login-plist" {
            do { try FileHandle.standardOutput.write(contentsOf: LoginItemManager().plistData(appURL: app, loginStarter: mode == "--print-login-plist")) }
            catch { fail(error.localizedDescription) }
            return
        }
        if let mode {
            do { try LoginItemManager().setEnabled(mode == "--install", appURL: app) }
            catch { fail(error.localizedDescription) }
            return
        }
        let directory = StateStore.defaultDirectory
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { fail(error.localizedDescription) }
        // launchd normally guarantees one instance. Lock also covers accidental direct invocations.
        let lock = open(directory.appendingPathComponent("agent.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { fail("Cannot open agent lock") }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { return }
        let history = AgentHistoryStore(directory: directory)
        while !Task.isCancelled {
            let running = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == "com.pauseguard.app" || $0.bundleURL?.resolvingSymlinksInPath() == app
            }
            do {
                let decision = try history.decision(session: StateStore(directory: directory).loadSession(), appRunning: running, now: Date())
                if decision == .relaunch {
                    // Recheck explicit exit and liveness at the last boundary before launch.
                    if StateStore(directory: directory).loadSession()?.desiredRunning == true,
                       !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.pauseguard.app" }) {
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.activates = false
                        _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
                    }
                }
            } catch { fputs("PauseGuard recovery: \(error.localizedDescription)\n", stderr) }
            try? await Task.sleep(for: .seconds(10))
        }
    }
    static func fail(_ message: String) -> Never { fputs(message + "\n", stderr); exit(1) }
}
