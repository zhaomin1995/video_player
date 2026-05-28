import XCTest
import AVFoundation
@testable import Awesome_Player

private final class StubDelegate: ABLoopDelegate {
    var lastState: ABLoopState = .inactive
    var seekTargets: [CMTime] = []
    func abLoopStateChanged(_ state: ABLoopState) { lastState = state }
    func abLoopShouldSeek(to time: CMTime) { seekTargets.append(time) }
}

final class ABLoopControllerTests: XCTestCase {
    private func t(_ seconds: Double) -> CMTime {
        CMTimeMakeWithSeconds(seconds, preferredTimescale: 600)
    }

    func testToggleProgressesInactiveSettingActiveInactive() {
        let c = ABLoopController()
        let d = StubDelegate(); c.delegate = d
        XCTAssertFalse(c.isActive)

        c.toggle(currentTime: t(10))
        if case .settingA(let a) = c.state {
            XCTAssertEqual(CMTimeGetSeconds(a), 10, accuracy: 0.01)
        } else { XCTFail("expected .settingA after first toggle") }

        c.toggle(currentTime: t(30))
        XCTAssertTrue(c.isActive)
        if case .active(let a, let b) = c.state {
            XCTAssertEqual(CMTimeGetSeconds(a), 10, accuracy: 0.01)
            XCTAssertEqual(CMTimeGetSeconds(b), 30, accuracy: 0.01)
        } else { XCTFail("expected .active after second toggle") }

        c.toggle(currentTime: t(45))
        XCTAssertFalse(c.isActive)
    }

    func testSecondToggleBeforeFirstSwapsAB() {
        let c = ABLoopController()
        c.toggle(currentTime: t(30))      // A = 30
        c.toggle(currentTime: t(10))      // B placed at 30, A at 10 (reversed)
        guard case .active(let a, let b) = c.state else { return XCTFail() }
        XCTAssertEqual(CMTimeGetSeconds(a), 10, accuracy: 0.01)
        XCTAssertEqual(CMTimeGetSeconds(b), 30, accuracy: 0.01)
    }

    func testCheckLoopSeeksAtAndPastB() {
        let c = ABLoopController()
        let d = StubDelegate(); c.delegate = d
        c.toggle(currentTime: t(10))
        c.toggle(currentTime: t(20))

        c.checkLoop(currentTime: t(19))   // before B — no seek
        XCTAssertTrue(d.seekTargets.isEmpty)

        c.checkLoop(currentTime: t(20))   // exactly at B — should seek
        XCTAssertEqual(d.seekTargets.count, 1)
        XCTAssertEqual(CMTimeGetSeconds(d.seekTargets[0]), 10, accuracy: 0.01)

        c.checkLoop(currentTime: t(25))   // past B — should also seek
        XCTAssertEqual(d.seekTargets.count, 2)
    }

    func testInactiveCheckLoopDoesNothing() {
        let c = ABLoopController()
        let d = StubDelegate(); c.delegate = d
        c.checkLoop(currentTime: t(50))
        XCTAssertTrue(d.seekTargets.isEmpty)
    }

    func testClearResetsState() {
        let c = ABLoopController()
        c.toggle(currentTime: t(10))
        c.toggle(currentTime: t(20))
        c.clear()
        XCTAssertFalse(c.isActive)
        if case .inactive = c.state {} else { XCTFail("clear() should restore .inactive") }
    }
}
