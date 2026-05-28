import XCTest
@testable import Awesome_Player

/// LanguageManager has tricky launch-vs-runtime semantics (Bundle.main.
/// preferredLocalizations is frozen at launch, English is the source
/// language with no .lproj, etc). These tests pin the contract that L()
/// returns the source key when English is active.
final class LanguageManagerTests: XCTestCase {
    func testEnglishReturnsKeyVerbatim() {
        LanguageManager.shared.setLanguage("en")
        XCTAssertEqual(L("Play"), "Play")
        XCTAssertEqual(L("Some Brand-New String That Has No Translation"),
                       "Some Brand-New String That Has No Translation")
    }

    func testActiveLanguageRoundTrips() {
        LanguageManager.shared.setLanguage("zh-Hans")
        XCTAssertEqual(LanguageManager.shared.currentLanguage, "zh-Hans")
        LanguageManager.shared.setLanguage(nil)
        XCTAssertNil(LanguageManager.shared.currentLanguage,
                     "Passing nil means 'follow system' — currentLanguage should be nil")
    }

    func testSettingUnknownLanguageDoesNotCrash() {
        LanguageManager.shared.setLanguage("xx-ZZ")
        // Falls back gracefully — L() should still return the key (since
        // no bundle was found for xx-ZZ, the source key is returned).
        XCTAssertFalse(L("Play").isEmpty)
    }
}
