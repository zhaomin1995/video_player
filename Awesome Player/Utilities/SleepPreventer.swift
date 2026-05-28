import Foundation
import AppKit

/// Keeps macOS awake while playback is active.
///
/// Uses `ProcessInfo.beginActivity(options:)`. Two activity flavors:
/// - `idleDisplaySleepDisabled` — keeps the display on (the right thing for
///   video; you want to see the frame).
/// - `idleSystemSleepDisabled` — only blocks system sleep, display can blank
///   (the right thing for audio-only playback so the laptop doesn't burn
///   battery lighting a black screen for an hour-long podcast).
///
/// Hooks: `engage(hasVideo:)` is called from PlayerViewController on play and
/// when the engine swap settles; `release()` on pause/stop. Both are idempotent
/// — re-engaging with the same flavor is a no-op. Switching flavors
/// (video↔audio) ends the prior activity and starts a fresh one.
///
/// Run `pmset -g assertions | grep -A2 "Awesome Player"` in Terminal to verify
/// the activity is actually held.
final class SleepPreventer {
    static let shared = SleepPreventer()

    private var token: NSObjectProtocol?
    private var currentFlavorAllowsScreenSaver: Bool = false

    private init() {}

    func engage(hasVideo: Bool) {
        let allowScreenSaver = !hasVideo
            && UserDefaults.standard.bool(forKey: Defaults.allowScreenSaverForAudio)
        // No-op if the current activity already matches what we want
        if token != nil, currentFlavorAllowsScreenSaver == allowScreenSaver { return }
        release()

        let options: ProcessInfo.ActivityOptions = allowScreenSaver
            ? [.idleSystemSleepDisabled]
            : [.idleSystemSleepDisabled, .idleDisplaySleepDisabled]
        let reason = allowScreenSaver
            ? "Awesome Player audio playback"
            : "Awesome Player video playback"
        token = ProcessInfo.processInfo.beginActivity(options: options, reason: reason)
        currentFlavorAllowsScreenSaver = allowScreenSaver
        dlog(.player, "SleepPreventer engaged (allowScreenSaver=\(allowScreenSaver))")
    }

    func release() {
        guard let t = token else { return }
        ProcessInfo.processInfo.endActivity(t)
        token = nil
        dlog(.player, "SleepPreventer released")
    }
}
