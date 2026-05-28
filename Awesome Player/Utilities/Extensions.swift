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
/// Routes through `LanguageManager.shared` so the in-app language picker can
/// swap locales at runtime without a relaunch.
///
/// Usage: `L("Play / Pause")`, `L("Volume: %d%%")`.
func L(_ key: String, comment: String = "") -> String {
    // English is the catalog's source language — Xcode does NOT emit an
    // en.lproj at build time, so we can't load one as a Bundle. Just return
    // the key (which IS the English string). Going through Bundle.main here
    // would return whatever language macOS picked AT APP LAUNCH (cached and
    // never re-evaluated), which is wrong for users who switch to English
    // from a non-English starting state.
    if LanguageManager.shared.isEnglish {
        return key
    }
    return LanguageManager.shared.bundle.localizedString(forKey: key, value: key, table: nil)
}

extension Notification.Name {
    /// Posted after LanguageManager.shared.setLanguage(...) finishes swapping
    /// the active bundle. Views that hold L()-derived static text in
    /// stringValue should observe this and re-apply L() to refresh in place.
    static let languageDidChange = Notification.Name("AwesomePlayer.LanguageDidChange")
}

/// Owns the active resource bundle that L() reads strings from. By default
/// this is Bundle.main (using whichever language macOS picked from
/// AppleLanguages at launch). When the user picks a specific language in
/// Preferences, we swap to that .lproj's bundle so new L() calls return the
/// chosen translations immediately — no relaunch.
///
/// We also write the choice to AppleLanguages so that:
/// 1. System dialogs (NSOpenPanel buttons, etc.) match next launch
/// 2. The setting persists across launches
final class LanguageManager {
    static let shared = LanguageManager()

    private var customBundle: Bundle?

    /// The .lproj language code the user explicitly picked ("en", "zh-Hans",
    /// "yue", …) or "" for "System Default" (follow Bundle.main).
    private(set) var effectiveLanguage: String = ""

    /// What Bundle.main resolved to at app launch. Used to determine whether
    /// System Default currently means English (so L() can take the fast
    /// key-pass-through path) without trusting Bundle.main's
    /// preferredLocalizations after AppleLanguages mutations.
    private let systemDefaultLang: String

    /// The active bundle L() reads from. nil → Bundle.main (System Default
    /// or a language without an emitted .lproj, like English).
    var bundle: Bundle { customBundle ?? .main }

    /// True when the active locale is English. L() uses this to short-circuit
    /// to "return the key directly" — required because Xcode doesn't emit an
    /// en.lproj for the source language, and Bundle.main is cached to the
    /// launch-time locale (often wrong after a runtime switch).
    var isEnglish: Bool {
        let active = effectiveLanguage.isEmpty ? systemDefaultLang : effectiveLanguage
        return active.hasPrefix("en")
    }

    /// The currently-active language code, or nil for System Default.
    var currentLanguage: String? {
        effectiveLanguage.isEmpty ? nil : effectiveLanguage
    }

    init() {
        // Snapshot what Bundle.main resolved to at app launch. preferredLocalizations
        // intersects the user's AppleLanguages preference with the bundle's
        // available .lproj directories — Apple guarantees the first entry is
        // the bundle's best match for the user's current settings.
        self.systemDefaultLang = Bundle.main.preferredLocalizations.first ?? "en"
        loadBundleFromDefaults()
    }

    private func loadBundleFromDefaults() {
        guard let lang = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first else {
            effectiveLanguage = ""
            customBundle = nil
            return
        }
        effectiveLanguage = lang
        // English has no .lproj — leave customBundle nil, L() handles via isEnglish
        if let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
           let b = Bundle(path: path) {
            customBundle = b
        } else {
            customBundle = nil
        }
    }

    /// `code` is the .lproj name (e.g. "zh-Hans", "yue", "en"), or nil to
    /// clear the override and follow the system locale.
    func setLanguage(_ code: String?) {
        if let code = code, !code.isEmpty {
            effectiveLanguage = code
            // Try to load a .lproj for the code. English ("en") has no .lproj
            // — that's OK, L() detects English via isEnglish and returns the
            // key directly instead of consulting customBundle.
            if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
               let b = Bundle(path: path) {
                customBundle = b
            } else {
                customBundle = nil
            }
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            effectiveLanguage = ""
            customBundle = nil
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        // synchronize() was a no-op since macOS 10.15 — UserDefaults flushes
        // automatically when the app suspends or terminates.
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }
}
