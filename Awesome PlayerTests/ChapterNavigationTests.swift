import XCTest
@testable import Awesome_Player

/// Regression tests for the chapter prev/next fix (bug #41).
/// Earlier code used ±1s and ±2s tolerances against the playhead, which
/// silently misbehaved at chapter boundaries less than the tolerance apart.
final class ChapterNavigationTests: XCTestCase {
    private let chapters: [[String: Any]] = [
        ["startTime": 0.0,    "title": "Intro"],
        ["startTime": 60.0,   "title": "Scene 1"],
        ["startTime": 180.0,  "title": "Scene 2"],
        ["startTime": 360.0,  "title": "Outro"],
    ]

    func testContainingChapterAtBoundary() {
        // Exactly at the start of chapter 2 — that's chapter 2, not chapter 1.
        XCTAssertEqual(ChapterNavigation.chapterIndexContaining(180.0, chapters: chapters), 2)
        // 0.1s before — still chapter 1.
        XCTAssertEqual(ChapterNavigation.chapterIndexContaining(179.9, chapters: chapters), 1)
    }

    func testContainingChapterBeforeFirst() {
        XCTAssertEqual(ChapterNavigation.chapterIndexContaining(-10, chapters: chapters), 0,
                       "Times before the first chapter clamp to index 0")
    }

    func testNextChapter() {
        // Inside Intro → Scene 1
        XCTAssertEqual(ChapterNavigation.nextChapterIndex(currentTime: 30, chapters: chapters), 1)
        // Inside Scene 1 → Scene 2
        XCTAssertEqual(ChapterNavigation.nextChapterIndex(currentTime: 120, chapters: chapters), 2)
        // Inside Outro → no more
        XCTAssertNil(ChapterNavigation.nextChapterIndex(currentTime: 400, chapters: chapters))
    }

    func testPreviousChapterEarlyInChapter() {
        // 1s into Scene 2 (within rewindThreshold) → jump to Scene 1
        XCTAssertEqual(ChapterNavigation.previousChapterIndex(currentTime: 181, chapters: chapters), 1)
    }

    func testPreviousChapterLateInChapter() {
        // 10s into Scene 2 (past rewindThreshold) → restart Scene 2
        XCTAssertEqual(ChapterNavigation.previousChapterIndex(currentTime: 190, chapters: chapters), 2)
    }

    func testPreviousChapterAtVeryStart() {
        XCTAssertEqual(ChapterNavigation.previousChapterIndex(currentTime: 0.5, chapters: chapters), 0,
                       "Even when before Intro+threshold, never go below 0")
    }

    func testEmptyChapters() {
        XCTAssertNil(ChapterNavigation.nextChapterIndex(currentTime: 10, chapters: []))
        XCTAssertNil(ChapterNavigation.previousChapterIndex(currentTime: 10, chapters: []))
    }

    func testCloselySpacedBoundaries() {
        // Reproduces a case the old ±2s tolerance misbehaved on:
        // two chapters less than 2s apart.
        let dense: [[String: Any]] = [
            ["startTime": 0.0],
            ["startTime": 1.0],   // <-- only 1s after the previous
            ["startTime": 2.5],
        ]
        // At 1.5s, we're in chapter 1 (covers [1.0, 2.5)). Old code would
        // have skipped to chapter 0 because (1.5 - 2 = -0.5 < 0).
        XCTAssertEqual(ChapterNavigation.chapterIndexContaining(1.5, chapters: dense), 1)
        // Previous from there → chapter 0 (we're under the rewind threshold)
        XCTAssertEqual(ChapterNavigation.previousChapterIndex(currentTime: 1.5, chapters: dense), 0)
    }
}
