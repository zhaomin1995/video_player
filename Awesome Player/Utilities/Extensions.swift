import Cocoa
import Foundation

/// Identifies file formats AVPlayer can handle natively (no remuxing needed).
extension URL {
    var isNativeAVPlayerFormat: Bool {
        let nativeExtensions = Set(["mp4", "m4v", "mov", "m4a", "aac", "mp3", "wav", "aiff"])
        if nativeExtensions.contains(pathExtension.lowercased()) { return true }
        if !isFileURL && (scheme == "http" || scheme == "https") && pathExtension.isEmpty { return true }
        return false
    }
}

/// Short alias for `NSLocalizedString` that uses the English string itself as
/// the lookup key. Pairs with the Xcode 15+ Localizable.xcstrings catalog —
/// when the catalog has no translation for the current locale, the source
/// English string is returned as the fallback.
///
/// Usage: `L("Play / Pause")`, `L("Volume: %d%%")`.
func L(_ key: String, comment: String = "") -> String {
    NSLocalizedString(key, comment: comment)
}
