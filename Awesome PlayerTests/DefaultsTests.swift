import XCTest
@testable import Awesome_Player

final class DefaultsTests: XCTestCase {
    /// `registerDefaults` is called from applicationDidFinishLaunching; the
    /// test target doesn't launch the app, so verify the keys exist and the
    /// registration is internally consistent (every key has a default value).
    func testRegisterDefaultsCoversKnownKeys() {
        Defaults.registerDefaults()
        let ud = UserDefaults.standard
        XCTAssertNotNil(ud.object(forKey: Defaults.theme))
        XCTAssertNotNil(ud.object(forKey: Defaults.defaultEngine))
        XCTAssertNotNil(ud.object(forKey: Defaults.defaultSpeed))
        XCTAssertNotNil(ud.object(forKey: Defaults.repeatMode))
        XCTAssertNotNil(ud.object(forKey: Defaults.defaultVolume))
        XCTAssertNotNil(ud.object(forKey: Defaults.convertHardwareEncoding))
        XCTAssertNotNil(ud.object(forKey: Defaults.videoDecodeMode))
        XCTAssertNotNil(ud.object(forKey: Defaults.smartZoomPercent))
    }

    /// Sanity-check numeric ranges so a typo in registerDefaults can't ship
    /// a nonsense default that breaks UI elements bound to these keys.
    func testNumericDefaultsAreInExpectedRanges() {
        Defaults.registerDefaults()
        let ud = UserDefaults.standard
        XCTAssertEqual(ud.double(forKey: Defaults.defaultSpeed), 1.0, accuracy: 0.001)
        XCTAssertEqual(ud.double(forKey: Defaults.shortSeekInterval), 5.0, accuracy: 0.001)
        XCTAssertEqual(ud.double(forKey: Defaults.longSeekInterval), 30.0, accuracy: 0.001)
        XCTAssertEqual(ud.double(forKey: Defaults.defaultVolume), 1.0, accuracy: 0.001)
        XCTAssertEqual(ud.integer(forKey: Defaults.smartZoomPercent), 100)
    }

    func testDefaultsKeysAreNamespaced() {
        // Catches accidental key collisions across feature areas: every key
        // is "<area>.<name>" so two features can't quietly overwrite each
        // other's preferences.
        let keys: [String] = [
            Defaults.theme, Defaults.defaultEngine, Defaults.defaultSpeed,
            Defaults.repeatMode, Defaults.defaultVolume, Defaults.subtitleFont,
            Defaults.singleClickAction, Defaults.castDefaultBehavior,
        ]
        for key in keys {
            XCTAssertTrue(key.contains("."), "Key \(key) should be namespaced with '.'")
        }
    }
}
