import AppKit
import CoreServices
import SwiftUI
import PauseGuardApp

@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var model: DesktopModel?
    private var sessionEnding = false
    private var powerOffObserver: NSObjectProtocol?
    override init() {
        super.init()
        powerOffObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sessionEnding = true
            }
        }
    }
    isolated deinit {
        if let powerOffObserver { NSWorkspace.shared.notificationCenter.removeObserver(powerOffObserver) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        // Quit Apple events carry a reason during logout/restart, before the
        // workspace notification may arrive. Ordinary menu quits have no reason.
        let reason = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue
        let systemQuit = reason.map { [OSType(kAEQuitAll), OSType(kAEShutDown), OSType(kAERestart), OSType(kAEReallyLogOut)].contains($0) } ?? false
        return model.requestTermination(systemSessionEnding: sessionEnding || systemQuit) ? .terminateNow : .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown(preservingSession: true) }
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
}
@main struct PauseGuardApplication: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @StateObject private var model: DesktopModel
    init() {
        let value = DesktopModel(demo: CommandLine.arguments.contains("--demo"))
        _model = StateObject(wrappedValue: value)
        delegate.model = value
    }
    var body: some Scene {
        MenuBarExtra("PauseGuard", systemImage: "leaf") {
            MenuBarView(model: model).onAppear { delegate.model = model }
        }.menuBarExtraStyle(.window)
        Window("PauseGuard 设置", id: "settings") {
            SettingsView(model: model).onAppear { delegate.model = model }
        }.defaultSize(width: 880, height: 680)
    }
}
