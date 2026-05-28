/// Lightweight logging façade.
///
/// `dlog` is a no-op in Release: the function body is empty under !DEBUG so
/// the compiler inlines it away to nothing, no string interpolation cost.
/// `wlog` (for "warning") always emits via `os_log`, so genuinely-anomalous
/// situations remain visible in Console.app on shipped builds without
/// leaking the firehose of opening-this-file / status-changed messages.
///
/// Earlier builds dumped everything to `print()`, which went to stderr and
/// to the unified log unfiltered — receiver names, file paths, and codec
/// IDs ended up in user diagnostic logs. Splitting into debug vs. warning
/// removes the noise without blinding us when something genuinely breaks.
import Foundation
import os

enum LogCategory: String {
    case player    = "Player"
    case vlc       = "VLC"
    case avplayer  = "AVPlayer"
    case cast      = "Cast"
    case dlna      = "DLNA"
    case http      = "HTTP"
    case audio     = "Audio"
}

@inline(__always)
func dlog(_ category: LogCategory, _ message: @autoclosure () -> String) {
    #if DEBUG
    print("[\(category.rawValue)] \(message())")
    #endif
}

private let _osLogs: [LogCategory: OSLog] = {
    let subsystem = Bundle.main.bundleIdentifier ?? "com.awesomeplayer"
    var map: [LogCategory: OSLog] = [:]
    for c in [LogCategory.player, .vlc, .avplayer, .cast, .dlna, .http, .audio] {
        map[c] = OSLog(subsystem: subsystem, category: c.rawValue)
    }
    return map
}()

/// Emits at `.default` level always; visible in Console.app even on shipped
/// builds. Use sparingly — anything that isn't an actionable warning should
/// be `dlog` instead.
func wlog(_ category: LogCategory, _ message: String) {
    os_log("%{public}@", log: _osLogs[category] ?? .default, type: .default, message)
}
