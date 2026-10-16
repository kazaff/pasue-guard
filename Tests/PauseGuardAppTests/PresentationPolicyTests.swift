import AppKit
import Testing
@testable import PauseGuardApp

@Suite @MainActor struct PresentationPolicyTests {
    @Test func strictDiscouragesSwitchingButPreservesSystemExit() {
        let strict = AppKitBreakBackend.options(strict: true)
        #expect(strict.contains(.disableProcessSwitching))
        #expect(strict.contains(.autoHideDock))
        #expect(strict.contains(.autoHideMenuBar))
        #expect(!strict.contains(.disableForceQuit))
        #expect(!strict.contains(.disableSessionTermination))
        #expect(!AppKitBreakBackend.options(strict: false).contains(.disableProcessSwitching))
    }
}
