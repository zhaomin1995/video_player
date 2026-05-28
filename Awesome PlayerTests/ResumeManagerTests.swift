import XCTest
@testable import Awesome_Player

/// ResumeManager has subtle threshold logic (min duration, min/max percent,
/// min absolute, min remaining) that's easy to silently break. These tests
/// pin the documented rules.
final class ResumeManagerTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/test-resume-fixture.mkv")

    override func setUp() {
        super.setUp()
        ResumeManager.clearPosition(for: url)
    }

    override func tearDown() {
        ResumeManager.clearPosition(for: url)
        super.tearDown()
    }

    func testShortClipsAreNotStored() {
        // Duration below 180s threshold → never store
        ResumeManager.savePosition(60, duration: 120, for: url)
        XCTAssertNil(ResumeManager.savedPosition(for: url))
    }

    func testFreshStartIsNotStored() {
        // Less than 60s in: not worth resuming
        ResumeManager.savePosition(30, duration: 6000, for: url)
        XCTAssertNil(ResumeManager.savedPosition(for: url))
    }

    func testEarlyPercentNotStored() {
        // 60s in but only 1% of a 6000s movie — bail
        ResumeManager.savePosition(60, duration: 6000, for: url)
        XCTAssertNil(ResumeManager.savedPosition(for: url),
                     "Position below 5% should not be stored even if past min-absolute")
    }

    func testNearEndNotStored() {
        // Past 95% — assume finished
        ResumeManager.savePosition(5800, duration: 6000, for: url)
        XCTAssertNil(ResumeManager.savedPosition(for: url),
                     "Position past 95% should not be stored")
    }

    func testNearEndByRemainingTime() {
        // Within 60s of end, but inside the 5-95% window → still rejected
        ResumeManager.savePosition(5950, duration: 6000, for: url)
        XCTAssertNil(ResumeManager.savedPosition(for: url),
                     "Less than 60s remaining should not be stored")
    }

    func testNormalCaseStores() {
        // 600s into a 6000s movie (10%) — meets all thresholds
        ResumeManager.savePosition(600, duration: 6000, for: url)
        XCTAssertEqual(ResumeManager.savedPosition(for: url) ?? 0, 600, accuracy: 0.01)
    }

    func testClearWipesPosition() {
        ResumeManager.savePosition(600, duration: 6000, for: url)
        XCTAssertNotNil(ResumeManager.savedPosition(for: url))
        ResumeManager.clearPosition(for: url)
        XCTAssertNil(ResumeManager.savedPosition(for: url))
    }
}
