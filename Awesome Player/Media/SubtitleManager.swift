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

    func loadEntries(_ newEntries: [SubtitleEntry]) {
        entries = newEntries
        currentIndex = 0
    }

    func loadSubtitleFromSRTText(_ srtText: String) {
        entries = SubtitleParser.parseSRTString(srtText)
        currentIndex = 0
    }

    func subtitle(at time: TimeInterval) -> SubtitleEntry? {
        let adjustedTime = time + delay

        if currentIndex < entries.count {
            let current = entries[currentIndex]
            if adjustedTime >= current.startTime && adjustedTime <= current.endTime {
                return current
            }
        }

        for (index, entry) in entries.enumerated() {
            if adjustedTime >= entry.startTime && adjustedTime <= entry.endTime {
                currentIndex = index
                return entry
            }
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
