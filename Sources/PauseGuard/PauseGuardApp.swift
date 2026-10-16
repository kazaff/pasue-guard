import AppKit
import SwiftUI
import PauseGuardApp

@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var model: DesktopModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard model.controller.requestQuit() else { return .terminateCancel }
        model.shutdown(); return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
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
