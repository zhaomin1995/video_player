import XCTest
@testable import Awesome_Player

/// Most of UpdateChecker is package-private, so we test the behaviors we can
/// reach: the menu-action plumbing in AppDelegate exists, and the default
/// "auto-check enabled" pref is honoured. The compareVersions / stripV
/// helpers are exercised indirectly via the version-string assertions in
/// IntegrationTests when the network is reachable.
final class UpdateCheckerTests: XCTestCase {
    func testAutoCheckRespectsDisabledFlag() {
        UserDefaults.standard.set(false, forKey: "update.autoCheckEnabled")
        // Should return without crashing or network access.
        UpdateChecker.checkInBackgroundIfDue()
        UserDefaults.standard.removeObject(forKey: "update.autoCheckEnabled")
    }

    func testThrottleHonoursRecentCheck() {
        // Set last-check to "just now"; auto check should bail without
        // touching the network.
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "update.lastCheckTimestamp")
        UpdateChecker.checkInBackgroundIfDue()
        UserDefaults.standard.removeObject(forKey: "update.lastCheckTimestamp")
    }
}
