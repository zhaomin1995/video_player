import Cocoa

/// Identifies file formats AVPlayer can handle natively (no remuxing needed).
extension URL {
    var isNativeAVPlayerFormat: Bool {
        let nativeExtensions = Set(["mp4", "m4v", "mov", "m4a", "aac", "mp3", "wav", "aiff"])
        if nativeExtensions.contains(pathExtension.lowercased()) { return true }
        if !isFileURL && (scheme == "http" || scheme == "https") && pathExtension.isEmpty { return true }
        return false
    }
}
