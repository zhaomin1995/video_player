import Cocoa
import CoreMedia

extension CMTime {
    var displayString: String {
        guard isValid, !isIndefinite else { return "0:00" }
        let totalSeconds = Int(CMTimeGetSeconds(self))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

extension URL {
    var isVideoFile: Bool {
        let videoExtensions = Set([
            "mp4", "m4v", "mov", "mkv", "avi", "wmv", "flv", "webm",
            "mpg", "mpeg", "ts", "mts", "m2ts", "vob", "3gp", "ogv",
            "rm", "rmvb", "asf", "divx", "f4v", "mxf", "ivf",
        ])
        return videoExtensions.contains(pathExtension.lowercased())
    }

    var isAudioFile: Bool {
        let audioExtensions = Set([
            "mp3", "aac", "m4a", "flac", "wav", "aiff", "ogg",
            "wma", "ac3", "dts", "opus",
        ])
        return audioExtensions.contains(pathExtension.lowercased())
    }

    var isMediaFile: Bool {
        isVideoFile || isAudioFile
    }

    var isNativeAVPlayerFormat: Bool {
        let nativeExtensions = Set(["mp4", "m4v", "mov", "m4a", "aac", "mp3", "wav", "aiff"])
        return nativeExtensions.contains(pathExtension.lowercased())
    }
}

extension NSColor {
    static let dvPlayerAccent = NSColor.controlAccentColor
}

class GradientScrimView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func updateLayer() {
        let gradient = CAGradientLayer()
        gradient.frame = bounds
        gradient.colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.6).cgColor,
            NSColor.black.withAlphaComponent(0.85).cgColor,
        ]
        gradient.locations = [0.0, 0.5, 1.0]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.sublayers?.removeAll()
        layer?.addSublayer(gradient)
    }

    override func layout() {
        super.layout()
        layer?.sublayers?.first?.frame = bounds
    }
}
