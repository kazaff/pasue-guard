import Foundation
import Testing
@testable import PauseGuardApp
import PauseGuardCore

@Suite struct PreferencesTests {
    @Test func validationAndRandomMessage() {
        var value = AppPreferences()
        value.customMessages = ["  ", "  看向远方  ", "\n伸展一下\n"]
        #expect(value.validated().customMessages == ["看向远方", "伸展一下"])
        for _ in 0..<20 { #expect(["看向远方", "伸展一下"].contains(value.randomMessage())) }
        #expect(!AppPreferences().randomMessage().isEmpty)
        let timing = UserSettings(workDurationSeconds: 0, breakDurationSeconds: 99999, preBreakWarningSeconds: 99)
        #expect(timing.workDurationSeconds == 300)
        #expect(timing.breakDurationSeconds == 3600)
        #expect(timing.preBreakWarningSeconds == 60)
    }
    @Test func realStorageAndFutureVersionPreservation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PreferencesStore(directory: root)
        var value = AppPreferences(); value.onboardingComplete = true; value.singleImage = true
        value.customMessages = ["  hello "]
        try store.save(value)
        #expect(store.load() == value.validated())
        let file = root.appendingPathComponent("preferences.json")
        try Data("{\"schemaVersion\":999}".utf8).write(to: file)
        #expect(store.load() == AppPreferences())
        try store.save(value)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.contains("preserved") })
    }
}
