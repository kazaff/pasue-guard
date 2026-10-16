import AppKit
import Combine
import PauseGuardCore
import PauseGuardImages
import PauseGuardPlatform

/// Lifetime owner for presentation and UI storage. No covers until an available break.
@MainActor public final class DesktopModel: ObservableObject {
    public let controller: AppController
    public let background: ImageBackgroundProvider
    public let libraryURL: URL
    @Published public var preferences: AppPreferences
    @Published public private(set) var assets: [ImageAsset] = []
    @Published public private(set) var themes: [BreakTheme] = []
    @Published public private(set) var busy = false
    @Published public var error: String?
    @Published public private(set) var loginItemInstalled = false
    @Published public private(set) var loginCleanupRequired = false
    @Published public private(set) var loginCleanupPaths: [String] = []
    public let isDemo: Bool
    private let preferencesStore: PreferencesStore
    private let setLoginEnabled: (Bool) throws -> Void
    private let readLoginItemPaths: () -> [String]
    private let covers: BreakWindowController
    private var subscriptions = Set<AnyCancellable>()
    private var screensObserver: NSObjectProtocol?
    private var preparedCycle: Int?
    private var messageCycle: Int?
    private var snapshotRevision = UUID()
    private var failureRecovery: Task<Void, Never>?
    public convenience init(demo: Bool = false) {
        self.init(demo: demo, directory: nil, controller: nil, covers: BreakWindowController(), observeScreens: true)
    }
    init(demo: Bool = false, directory injectedDirectory: URL?, controller injectedController: AppController?,
         covers: BreakWindowController, observeScreens: Bool = false,
         setLoginEnabled: @escaping (Bool) throws -> Void = { try LoginItemManager().setEnabled($0, appURL: Bundle.main.bundleURL) },
         loginItemPaths: @escaping () -> [String] = { LoginItemManager().remainingPaths }) {
        self.setLoginEnabled = setLoginEnabled
        self.readLoginItemPaths = loginItemPaths
        self.covers = covers
        isDemo = demo
        let directory = injectedDirectory ?? (demo ? FileManager.default.temporaryDirectory.appendingPathComponent("PauseGuard-demo-" + UUID().uuidString) : StateStore.defaultDirectory)
        let store = StateStore(directory: directory)
        preferencesStore = PreferencesStore(directory: directory)
        preferences = preferencesStore.load()
        libraryURL = directory.appendingPathComponent("Images")
        background = ImageBackgroundProvider(libraryURL: libraryURL)
        if let injectedController { controller = injectedController } else if demo {
            try? store.saveSettings(UserSettings(workDurationSeconds: 300, breakDurationSeconds: 60, strictMode: false))
            let origin = SystemClock.snapshot()
            controller = AppController(store: store, clock: {
                var now = SystemClock.snapshot()
                now.continuousUptime = origin.continuousUptime + (now.continuousUptime - origin.continuousUptime) * 15
                return now
            }, idleSeconds: { 0 })
        } else { controller = AppController(store: store) }
        if !demo {
            loginCleanupPaths = loginItemPaths()
            loginItemInstalled = !loginCleanupPaths.isEmpty
            loginCleanupRequired = loginItemInstalled && (!preferences.loginAtLaunch || loginCleanupPaths.count != 2)
        }
        covers.onFailure = { [weak self] error in
            guard let self, self.failureRecovery == nil else { return }
            // @Published emits in willSet. Recover after the outer engine send
            // finishes assigning/persisting runtime, never reenter that publication.
            self.failureRecovery = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.failureRecovery = nil
                self.controller.presentationFailed(error)
            }
        }
        controller.$runtime.sink { [weak self] runtime in self?.present(runtime) }.store(in: &subscriptions)
        if observeScreens {
            screensObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.prepareBackground() }
            }
        }
        Task { [weak self] in await self?.reloadLibrary() }
    }
    isolated deinit { if let screensObserver { NotificationCenter.default.removeObserver(screensObserver) } }
    private func present(_ runtime: RuntimeState) {
        objectWillChange.send()
        if runtime.phase == .breaking && runtime.isAvailable {
            if messageCycle != runtime.cycleNumber {
                messageCycle = runtime.cycleNumber
                covers.message = preferences.randomMessage()
                covers.reduceVisualStimulation = preferences.reduceVisualStimulation
            }
            do { try covers.show(runtime: runtime, background: background) { [weak controller] in controller?.send($0) } } catch { /* onFailure performs recovery once */ }
        } else {
            covers.dismiss()
            if [.working, .preparing].contains(runtime.phase), preparedCycle != runtime.cycleNumber {
                preparedCycle = runtime.cycleNumber
                background.prepare(for: DisplayTopology.current(), singleImage: preferences.singleImage)
            }
        }
    }
    public var editingAllowed: Bool { controller.runtime.phase != .breaking }
    public func savePreferences() {
        guard editingAllowed else { return }
        preferences = preferences.validated()
        do { try preferencesStore.save(preferences); prepareBackground() } catch { self.error = error.localizedDescription }
    }
    public func setLoginAtLaunch(_ enabled: Bool) {
        guard editingAllowed, !isDemo else { return }
        let oldPreference = preferences.loginAtLaunch
        let oldInstalled = loginItemInstalled
        do { try setLoginEnabled(enabled) }
        catch {
            refreshLoginStatus()
            loginCleanupRequired = loginItemInstalled
            self.error = error.localizedDescription
            return
        }
        loginItemInstalled = enabled
        loginCleanupPaths = readLoginItemPaths()
        preferences.loginAtLaunch = enabled
        // Cleanup of an already-disabled preference must not reinstall jobs just
        // because unrelated preference storage is still unavailable.
        if enabled == oldPreference {
            loginCleanupRequired = false
            error = nil
            return
        }
        do {
            try preferencesStore.save(preferences)
            loginCleanupRequired = false
            error = nil
        } catch let saveError {
            preferences.loginAtLaunch = oldPreference
            do {
                try setLoginEnabled(oldInstalled)
                refreshLoginStatus()
                loginCleanupRequired = loginItemInstalled && !oldPreference
                error = saveError.localizedDescription
            } catch let rollbackError {
                refreshLoginStatus()
                loginCleanupRequired = true
                error = "保存登录设置失败：" + saveError.localizedDescription + "\n回滚登录组件失败：" + rollbackError.localizedDescription
            }
        }
    }
    private func refreshLoginStatus() {
        loginCleanupPaths = readLoginItemPaths()
        loginItemInstalled = !loginCleanupPaths.isEmpty
    }
    public func retryLoginCleanup() { setLoginAtLaunch(false) }
    public func start() { preferences.onboardingComplete = true; savePreferences(); controller.send(.start) }
    public func shutdown() { failureRecovery?.cancel(); failureRecovery = nil; covers.dismiss(); background.invalidate(); controller.shutdown() }
    public func prepareBackground() {
        guard [.working, .preparing].contains(controller.runtime.phase) else { return }
        background.prepare(for: DisplayTopology.current(), singleImage: preferences.singleImage)
    }
    public func reloadLibrary() async {
        let revision = UUID(); snapshotRevision = revision
        do {
            let snapshot = try await background.librarySnapshot()
            guard snapshotRevision == revision else { return }
            assets = snapshot.assets; themes = snapshot.themes
        } catch { self.error = error.localizedDescription }
    }
    public func importImages() {
        guard editingAllowed, !busy else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .heif]
        guard panel.runModal() == .OK else { return }
        mutate { [background] in _ = try await background.importImages(panel.urls) }
    }
    public func removeImage(_ id: UUID) { mutate { [background] in try await background.removeImage(id: id) } }
    public func saveThemes(_ value: [BreakTheme]) { mutate { [background] in try await background.saveThemes(value) } }
    private func mutate(_ action: @escaping @MainActor () async throws -> Void) {
        guard editingAllowed, !busy else { return }; busy = true
        Task { [weak self] in
            do { try await action(); await self?.reloadLibrary(); self?.prepareBackground() } catch { self?.error = error.localizedDescription }
            self?.busy = false
        }
    }
}
