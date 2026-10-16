import Testing
import Foundation
@testable import PauseGuardPlatform

@Suite struct DisplayTopologyTests {
    func display(_ id: UInt32, main: Bool = false, x: Double = 0) -> DisplayDescriptor {
        DisplayDescriptor(id: id, frame: CGRect(x: x, y: 0, width: 1920, height: 1080), scale: 2, isMain: main)
    }
    @Test func testHotPlugAddsOnlyNewDisplay() {
        let changes = DisplayTopology.diff(previous: [display(1)], current: [display(1), display(2)])
        #expect(changes.added.map(\.id) == [2])
        #expect(changes.removed.isEmpty)
        #expect(changes.updated.isEmpty)
    }
    @Test func testMainDisplayChangeKeepsCoverage() {
        let changes = DisplayTopology.diff(previous: [display(1, main: true), display(2)], current: [display(1), display(2, main: true)])
        #expect(changes.added.isEmpty)
        #expect(changes.removed.isEmpty)
        #expect(Set(changes.updated.map(\.id)) == [1, 2])
    }
    @Test func testRemovedDisplayIsReleased() {
        let changes = DisplayTopology.diff(previous: [display(1), display(2)], current: [display(2, x: 100)])
        #expect(changes.removed.map(\.id) == [1])
        #expect(changes.updated.map(\.id) == [2])
    }
}
