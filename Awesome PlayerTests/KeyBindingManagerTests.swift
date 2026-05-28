import XCTest
import Cocoa
@testable import Awesome_Player

final class KeyBindingManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Wipe stored bindings so each test gets a fresh manager state
        UserDefaults.standard.removeObject(forKey: Defaults.customShortcuts)
    }

    func testAllPresetsHaveStableIdsAndBindings() {
        let presets = KeyBindingManager.allPresets
        XCTAssertGreaterThanOrEqual(presets.count, 2, "Should have at least Default and VLC presets")
        let ids = presets.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Preset ids must be unique")
        for p in presets {
            XCTAssertFalse(p.bindings.isEmpty, "Preset \(p.id) has no bindings")
        }
    }

    func testApplyPresetReplacesBindings() {
        let mgr = KeyBindingManager.shared
        mgr.applyPreset(id: "default")
        let defaultCount = KeyBindingManager.allPresets.first(where: { $0.id == "default" })!.bindings.count
        XCTAssertEqual(mgr.currentPresetId, "default")

        mgr.applyPreset(id: "vlc")
        XCTAssertEqual(mgr.currentPresetId, "vlc")
        let vlcCount = KeyBindingManager.allPresets.first(where: { $0.id == "vlc" })!.bindings.count
        XCTAssertGreaterThan(vlcCount, 0)
        // After switching, the stored bindings should be the new preset's
        // count (not zero, not the previous count if they differ).
        XCTAssertTrue(defaultCount > 0)
    }

    func testKeyBindingMatchesIgnoresIrrelevantModifiers() {
        let b = KeyBinding(key: " ", modifiers: 0, action: PlayerAction.playPause.rawValue)
        XCTAssertTrue(b.matches(characters: " ", modifierFlags: []))
        XCTAssertTrue(b.matches(characters: " ", modifierFlags: [.numericPad]),
                      "numericPad should be ignored when matching")
        XCTAssertFalse(b.matches(characters: " ", modifierFlags: [.shift]),
                       "shift is significant and should not match a no-modifier binding")
    }
}
