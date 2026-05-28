/// Pure helpers for chapter navigation.
///
/// Extracted out of PlayerViewController so the boundary logic can be tested
/// without spinning up the whole VC + engines. The earlier in-VC version
/// used fuzzy ±2s / ±1s tolerances on the playhead, which silently misbehaved
/// at chapter boundaries less than the tolerance apart (rare but real in
/// concert recordings or chapter-per-song audio). These helpers use the
/// "containing chapter" definition: the chapter whose [start, nextStart)
/// range covers `time`.
import Foundation

enum ChapterNavigation {
    /// Returns the index of the chapter whose [start, nextStart) range
    /// contains `time`. Assumes chapters are sorted ascending by startTime.
    /// Returns 0 when `time` precedes the first chapter.
    static func chapterIndexContaining(_ time: Double, chapters: [[String: Any]]) -> Int {
        var idx = 0
        for (i, ch) in chapters.enumerated() {
            let start = ch["startTime"] as? Double ?? 0
            if start <= time { idx = i } else { break }
        }
        return idx
    }

    /// Returns the next chapter index to seek to, or nil if there is none.
    static func nextChapterIndex(currentTime: Double, chapters: [[String: Any]]) -> Int? {
        guard !chapters.isEmpty else { return nil }
        let containing = chapterIndexContaining(currentTime, chapters: chapters)
        let target = containing + 1
        return target < chapters.count ? target : nil
    }

    /// Returns the previous chapter index. If the playhead is more than
    /// `rewindThreshold` seconds into the current chapter, "previous"
    /// restarts the current chapter (matches the iTunes/VLC behavior).
    static func previousChapterIndex(currentTime: Double,
                                     chapters: [[String: Any]],
                                     rewindThreshold: Double = 3.0) -> Int? {
        guard !chapters.isEmpty else { return nil }
        let containing = chapterIndexContaining(currentTime, chapters: chapters)
        let start = chapters[containing]["startTime"] as? Double ?? 0
        if currentTime - start > rewindThreshold {
            return containing  // Restart current chapter
        }
        return max(0, containing - 1)
    }
}
