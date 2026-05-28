/// Lightweight update checker for GitHub-released builds.
///
/// We don't ship Sparkle because the app is distributed unsigned via GitHub
/// Releases — there's no notarized appcast pipeline and no EdDSA key. Instead
/// we poll the GitHub Releases API on launch (throttled), compare tag_name to
/// CFBundleShortVersionString, and surface an alert that opens the release
/// page in the browser. The user does the download/replace themselves.
///
/// Throttling: at most one check per `minCheckIntervalHours`. The last-check
/// timestamp lives in UserDefaults so it survives relaunch.
///
/// Concurrency: uses async/await on URLSession. Earlier versions blocked a
/// background worker thread with `DispatchSemaphore.wait` for up to 12s on
/// every launch — wasted thread + slower app activation.
import Cocoa

enum UpdateChecker {
    private static let owner = "zhaomin1995"
    private static let repo = "awesome_player"
    private static let lastCheckKey = "update.lastCheckTimestamp"
    private static let skipVersionKey = "update.skippedVersion"
    private static let autoCheckKey = "update.autoCheckEnabled"
    private static let minCheckIntervalHours: TimeInterval = 24

    /// Call from app launch. Silently no-ops if disabled or recently checked.
    static func checkInBackgroundIfDue() {
        let ud = UserDefaults.standard
        if ud.object(forKey: autoCheckKey) != nil && !ud.bool(forKey: autoCheckKey) { return }
        let last = ud.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        if now - last < minCheckIntervalHours * 3600 { return }
        // 3s delay so we don't fight with launch animations / window placement
        Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await performCheck(showUpToDate: false)
        }
    }

    /// Call from the "Check for Updates…" menu item. Always shows a result
    /// alert (including "you're up to date").
    static func checkNow() {
        Task.detached(priority: .userInitiated) {
            await performCheck(showUpToDate: true)
        }
    }

    @MainActor
    private static func performCheck(showUpToDate: Bool) async {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)

        guard let release = await fetchLatestRelease() else {
            if showUpToDate {
                let alert = NSAlert()
                alert.messageText = L("Could not check for updates")
                alert.informativeText = L("Please check your internet connection and try again.")
                alert.runModal()
            }
            return
        }

        let current = currentVersion()
        let latest = stripV(release.tag)
        let skipped = UserDefaults.standard.string(forKey: skipVersionKey)

        if compareVersions(latest, current) <= 0 {
            if showUpToDate {
                let alert = NSAlert()
                alert.messageText = L("You're up to date")
                alert.informativeText = String(format: L("Awesome Player %@ is the latest version."), current)
                alert.runModal()
            }
            return
        }
        if !showUpToDate && skipped == latest { return }

        let alert = NSAlert()
        alert.messageText = String(format: L("A new version is available: %@"), latest)
        alert.informativeText = String(format: L("You have %@. Open the release page to download the latest build."), current)
        alert.addButton(withTitle: L("Open Release Page"))
        alert.addButton(withTitle: L("Skip This Version"))
        alert.addButton(withTitle: L("Remind Me Later"))
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            if let url = URL(string: release.htmlURL) { NSWorkspace.shared.open(url) }
        case .alertSecondButtonReturn:
            UserDefaults.standard.set(latest, forKey: skipVersionKey)
        default:
            break
        }
    }

    private struct Release { let tag: String; let htmlURL: String }

    private static func fetchLatestRelease() async -> Release? {
        let urlStr = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let html = json["html_url"] as? String else { return nil }
            return Release(tag: tag, htmlURL: html)
        } catch {
            return nil
        }
    }

    private static func currentVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0"
    }

    private static func stripV(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Returns 1 if a>b, -1 if a<b, 0 if equal. Parses dotted-int versions.
    private static func compareVersions(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }
}
