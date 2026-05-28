import Foundation

class SubtitleManager {
    private var entries: [SubtitleEntry] = []
    private var currentIndex = 0
    private(set) var isVisible = true
    var delay: TimeInterval = 0

    func loadSubtitle(from url: URL) {
        entries = SubtitleParser.parse(url: url)
        currentIndex = 0
    }

    func loadSubtitleFromSRTText(_ srtText: String) {
        entries = SubtitleParser.parseSRTString(srtText)
        currentIndex = 0
    }

    /// Called from the time-observer tick (~4×/s for AVPlayer, 1×/s for VLC).
    /// Hot path: avoid linear scan when the user is scrubbing through an ASS
    /// file with thousands of cues.
    ///
    /// Strategy:
    ///   1. Fast path — the playhead is usually inside `currentIndex` or
    ///      its immediate neighbours (normal monotonic playback). Probe
    ///      currentIndex, then ±1. O(1) for ~99% of ticks.
    ///   2. Fall back to binary search over `entries` sorted by startTime
    ///      (SubtitleParser already returns them sorted). O(log n).
    func subtitle(at time: TimeInterval) -> SubtitleEntry? {
        let adjustedTime = time + delay
        guard !entries.isEmpty else { return nil }

        // 1) Probe currentIndex and its neighbours
        for offset in [0, 1, -1] {
            let i = currentIndex + offset
            guard i >= 0, i < entries.count else { continue }
            let e = entries[i]
            if adjustedTime >= e.startTime && adjustedTime <= e.endTime {
                currentIndex = i
                return e
            }
        }

        // 2) Binary search by startTime — find the rightmost entry whose
        // startTime <= adjustedTime, then verify it also covers endTime.
        var lo = 0
        var hi = entries.count - 1
        var candidate = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if entries[mid].startTime <= adjustedTime {
                candidate = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        guard candidate >= 0 else { return nil }
        let e = entries[candidate]
        if adjustedTime <= e.endTime {
            currentIndex = candidate
            return e
        }
        return nil
    }

    func toggleVisibility() {
        isVisible.toggle()
    }

    func adjustDelay(by amount: TimeInterval) {
        delay += amount
    }

    func clear() {
        entries = []
        currentIndex = 0
        delay = 0
    }

    var hasSubtitles: Bool {
        !entries.isEmpty
    }

    static func findSubtitleFiles(for videoURL: URL) -> [URL] {
        let directory = videoURL.deletingLastPathComponent()
        let videoName = videoURL.deletingPathExtension().lastPathComponent
        let subtitleExtensions = Set(["srt", "ass", "ssa", "vtt", "sub", "sup", "idx"])

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents.filter { url in
            let ext = url.pathExtension.lowercased()
            guard subtitleExtensions.contains(ext) else { return false }
            let name = url.deletingPathExtension().lastPathComponent
            return name.hasPrefix(videoName)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
