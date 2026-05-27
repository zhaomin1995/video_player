import Cocoa

class MediaInspectorController: NSWindowController {
    private let textView = NSTextView()

    init() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 350),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow],
                            backing: .buffered, defer: false)
        window.title = L("Media Inspector")
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.minSize = NSSize(width: 300, height: 200)
        super.init(window: window)
        setupContent()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupContent() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView
        window?.contentView = scrollView
    }

    func updateInfo(for url: URL) {
        var lines: [String] = []
        lines.append("File: \(url.lastPathComponent)")
        lines.append("Path: \(url.path)")

        let probe = FFmpegBridge.probeFile(url.path)
        lines.append("")
        lines.append(L("--- Video ---"))
        if let codecName = FFmpegBridge.videoCodecName(forFile: url.path) {
            lines.append("Codec: \(codecName)")
        }
        lines.append("Resolution: \(probe.width) x \(probe.height)")
        lines.append("Duration: \(String(format: "%.1f", probe.duration))s")
        if probe.hasDolbyVision.boolValue { lines.append("Dolby Vision: Yes") }
        if probe.hasHDR.boolValue { lines.append("HDR: Yes") }

        lines.append("")
        lines.append(L("--- Audio ---"))
        lines.append("Tracks: \(probe.numAudioTracks)")
        lines.append("Channels: \(probe.audioChannels)")
        lines.append("Sample Rate: \(probe.audioSampleRate) Hz")

        let audioTracks = FFmpegBridge.audioTracks(forFile: url.path)
        for track in audioTracks {
            let codec = track["codec"] as? String ?? "?"
            let lang = track["language"] as? String ?? "und"
            let ch = track["channels"] as? Int ?? 0
            lines.append("  Track: \(codec), \(ch)ch, \(lang)")
        }

        lines.append("")
        lines.append(L("--- Subtitles ---"))
        lines.append("Tracks: \(probe.numSubtitleTracks)")
        let subTracks = FFmpegBridge.subtitleTracks(forFile: url.path)
        for track in subTracks {
            let codec = track["codec"] as? String ?? "?"
            let lang = track["language"] as? String ?? "und"
            lines.append("  Track: \(codec), \(lang)")
        }

        textView.string = lines.joined(separator: "\n")
    }
}
