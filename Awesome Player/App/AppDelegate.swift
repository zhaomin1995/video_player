import Cocoa
import AVFoundation
import CoreAudio
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: PlayerWindowController?
    private var preferencesController: PreferencesWindowController?
    private var miniPlayer: MiniPlayerWindowController?
    let castingManager = CastingManager()
    let nowPlayingController = NowPlayingController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Defaults.registerDefaults()
        applyTheme()
        MenuManager.setupMainMenu()

        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        windowController = PlayerWindowController()
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)

        // Force window to 0.7x screen size, overriding any macOS state restoration
        if let window = windowController?.window, let screen = window.screen ?? NSScreen.main {
            let w = screen.frame.width * 0.7
            let h = screen.frame.height * 0.7
            let x = screen.visibleFrame.origin.x + (screen.visibleFrame.width - w) / 2
            let y = screen.visibleFrame.origin.y + (screen.visibleFrame.height - h) / 2
            window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        }

        nowPlayingController.playerViewController = windowController?.playerViewController
        nowPlayingController.setup()

        NSApp.activate(ignoringOtherApps: true)

        castingManager.startAirPlayDiscovery()

        // Apply the saved theme immediately, then refresh on any prefs change.
        // UserDefaults doesn't expose individual keys as KVO properties, so the
        // standard modern pattern is to listen to didChangeNotification and
        // diff the value we care about. applyTheme() is idempotent + cheap
        // (a single switch), so we don't bother with caching the last value.
        applyTheme()
        themeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyTheme()
        }

        // Drop cached window controllers on language change so the next time
        // they're opened, their views are built with the new locale's strings.
        // PreferencesWindowController, MediaInspectorController and
        // VideoEQPanelController all bake L() values into NSTextField labels
        // at init time — recycling the cached instance would show stale text.
        NotificationCenter.default.addObserver(self, selector: #selector(languageDidChange),
                                                name: .languageDidChange, object: nil)

        UpdateChecker.checkInBackgroundIfDue()
    }

    @objc func checkForUpdatesAction(_ sender: Any?) {
        UpdateChecker.checkNow()
    }

    @objc func revealCrashLogsAction(_ sender: Any?) {
        // macOS writes crash reports to ~/Library/Logs/DiagnosticReports.
        // Filenames start with the executable name, so highlighting the
        // most recent matching one (if any) saves the user a scroll.
        let logsDir = ("~/Library/Logs/DiagnosticReports" as NSString).expandingTildeInPath
        let dirURL = URL(fileURLWithPath: logsDir)
        let exe = (Bundle.main.executableURL?.lastPathComponent ?? "Awesome Player")
        let fm = FileManager.default
        let crashes = (try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.lastPathComponent.hasPrefix(exe) }
            .sorted { (a, b) in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            } ?? []
        if let latest = crashes.first {
            NSWorkspace.shared.activateFileViewerSelecting([latest])
        } else {
            NSWorkspace.shared.open(dirURL)
        }
    }

    @objc func reportIssueAction(_ sender: Any?) {
        if let url = URL(string: "https://github.com/zhaomin1995/awesome_player/issues/new") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func languageDidChange() {
        // PreferencesWindowController refreshes itself in place via its own
        // .languageDidChange observer — no need to drop the cached instance.
        // Floating panels (Inspector, Video EQ) bake L() labels at init time
        // and don't yet have refresh logic; dropping them means the next
        // open builds fresh views with the new locale.
        inspectorController = nil
        videoEQController = nil
    }

    /// Token for the UserDefaults.didChangeNotification observer wired in
    /// applicationDidFinishLaunching. Removed in applicationWillTerminate.
    private var themeObserver: NSObjectProtocol?

    private func applyTheme() {
        let themeIndex = UserDefaults.standard.integer(forKey: Defaults.theme)
        switch themeIndex {
        case 1: NSApp.appearance = NSAppearance(named: .darkAqua)
        case 2: NSApp.appearance = NSAppearance(named: .aqua)
        default: NSApp.appearance = nil // system
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.playerViewController.saveCurrentPosition()
        // Mirror the observers wired in applicationDidFinishLaunching so
        // bookkeeping stays consistent if terminate is ever cancelled by a
        // save panel and the app continues running.
        if let token = themeObserver {
            NotificationCenter.default.removeObserver(token)
            themeObserver = nil
        }
        NotificationCenter.default.removeObserver(self, name: .languageDidChange, object: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        UserDefaults.standard.bool(forKey: Defaults.quitOnLastWindowClosed)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        RecentDocumentsMenuDelegate.addRecentFile(url)
        windowController?.openFile(url: url)
        return true
    }

    /// Handles `awesomeplayer://<encoded-url-or-path>` invocations from the
    /// bookmarklet, browser extensions, scripts, or anything else that fires
    /// a URL. Strips the awesomeplayer:// prefix and treats the remainder as
    /// either an http(s) media URL (route through URLOpenCoordinator's
    /// stream-resolution path) or a file path (open directly).
    ///
    /// Registered via the `CFBundleURLTypes` entry in Info.plist — macOS
    /// routes matching schemes here via this AppKit callback automatically.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "awesomeplayer" {
                // The body lives in absoluteString after the scheme; strip it
                // and unescape so embedded ?query strings come through intact.
                let stripped = String(url.absoluteString.dropFirst("awesomeplayer://".count))
                guard let decoded = stripped.removingPercentEncoding else { continue }
                routeIncomingURL(decoded)
            } else if url.isFileURL {
                windowController?.openFile(url: url)
            }
        }
    }

    private func routeIncomingURL(_ string: String) {
        // file:// prefix → unwrap to a local URL; bare path → file URL;
        // http(s):// → media URL routed through openStreamURL.
        if string.hasPrefix("file://"), let url = URL(string: string) {
            windowController?.openFile(url: url)
        } else if string.hasPrefix("http://") || string.hasPrefix("https://"),
                  let url = URL(string: string) {
            // Reuse the URL-open coordinator's resolution logic (yt-dlp for
            // YouTube etc., direct play for media URLs). Pass the URL in
            // pre-resolved so the dialog doesn't prompt the user.
            URLOpenCoordinator(windowController: windowController).openExternalURL(url)
        } else if FileManager.default.fileExists(atPath: string) {
            windowController?.openFile(url: URL(fileURLWithPath: string))
        }
    }

    /// macOS Services entry point. Configured in Info.plist's NSServices.
    /// User selects a URL or file path in any app, right-clicks → Services →
    /// "Play in Awesome Player". The pasteboard hands us the URL/text/file
    /// reference; we pipe it through the same routing as the URL-scheme path.
    @objc func handleServicesURL(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                if url.isFileURL { windowController?.openFile(url: url) }
                else { routeIncomingURL(url.absoluteString) }
            }
        } else if let strings = pboard.readObjects(forClasses: [NSString.self], options: nil) as? [String] {
            for s in strings { routeIncomingURL(s) }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let filename = filenames.first {
            let url = URL(fileURLWithPath: filename)
            RecentDocumentsMenuDelegate.addRecentFile(url)
            windowController?.openFile(url: url)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    // MARK: - File Menu

    @objc func openFileAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            RecentDocumentsMenuDelegate.addRecentFile(url)
            self?.windowController?.openFile(url: url)
        }
    }

    @objc func openURL(_ sender: Any?) {
        URLOpenCoordinator(windowController: windowController).begin()
    }


    @objc func addSubtitleFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "srt"),
            UTType(filenameExtension: "ass"),
            UTType(filenameExtension: "ssa"),
            UTType(filenameExtension: "vtt"),
            UTType(filenameExtension: "sub"),
        ].compactMap { $0 }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.windowController?.playerViewController.loadSubtitleFile(url)
        }
    }

    @objc func saveScreenshot(_ sender: Any?) {
        windowController?.playerViewController.saveScreenshot()
    }

    @objc func searchOpenSubtitlesAction(_ sender: Any?) {
        // Pre-populate the query with the current filename (no extension) so
        // the common case — searching for the currently-playing movie — is
        // one click. Strips quality/release tags after a few common
        // separators to give the search service a cleaner string.
        let seed: String = {
            guard let title = windowController?.playerViewController.currentFileURL?
                .deletingPathExtension().lastPathComponent else { return "" }
            // Cut at the first occurrence of a common rip/release separator
            // so "Movie.Name.2024.1080p.WEB-DL.x264" becomes "Movie Name".
            var cleaned = title
            for sep in [".1080p", ".720p", ".2160p", ".4K", ".WEB", ".BluRay", ".HDR"] {
                if let r = cleaned.range(of: sep, options: .caseInsensitive) {
                    cleaned = String(cleaned[..<r.lowerBound])
                }
            }
            return cleaned.replacingOccurrences(of: ".", with: " ")
                          .replacingOccurrences(of: "_", with: " ")
                          .trimmingCharacters(in: .whitespaces)
        }()

        let win = OpenSubtitlesSearchWindow(initialQuery: seed)
        win.onDownloaded = { [weak self] url in
            self?.windowController?.playerViewController.loadSubtitleFile(url)
        }
        win.showWindow(nil)
        win.window?.makeKeyAndOrderFront(nil)
        // Hold a strong reference so the window doesn't deallocate immediately
        objc_setAssociatedObject(self, &Self.openSubsWindowKey, win, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static var openSubsWindowKey: UInt8 = 0

    private var convertStreamController: ConvertStreamWindowController?

    @objc func showConvertStream(_ sender: Any?) {
        if convertStreamController == nil {
            convertStreamController = ConvertStreamWindowController()
        }
        convertStreamController?.showWindow(nil)
        convertStreamController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Playback Menu

    @objc func togglePlayPause(_ sender: Any?) {
        windowController?.playerViewController.togglePlayPause()
    }
    @objc func seekForward5(_ sender: Any?) {
        windowController?.playerViewController.seek(by: 5)
    }
    @objc func seekBackward5(_ sender: Any?) {
        windowController?.playerViewController.seek(by: -5)
    }
    @objc func stepFrameForward(_ sender: Any?) {
        windowController?.playerViewController.stepFrame(forward: true)
    }
    @objc func stepFrameBackward(_ sender: Any?) {
        windowController?.playerViewController.stepFrame(forward: false)
    }
    /// Toggle between main window and the compact mini player. Engine stays
    /// alive across the swap — both windows hold weak refs to the same
    /// PlayerViewController via different paths (main: direct child; mini:
    /// captured at init). Window-close routes back through here so the user
    /// always ends up with a visible window.
    @objc func beginInteractiveCrop(_ sender: Any?) {
        windowController?.playerViewController.beginInteractiveCrop()
    }

    @objc func showVideoFilters(_ sender: Any?) {
        VideoFiltersPanelController.shared.showWindow(nil)
        VideoFiltersPanelController.shared.window?.makeKeyAndOrderFront(nil)
    }

    @objc func toggleMiniPlayer(_ sender: Any?) {
        guard let vc = windowController?.playerViewController else { return }
        if let mini = miniPlayer, mini.window?.isVisible == true {
            mini.window?.orderOut(nil)
            windowController?.window?.makeKeyAndOrderFront(nil)
        } else {
            if miniPlayer == nil {
                miniPlayer = MiniPlayerWindowController(playerVC: vc)
            }
            windowController?.window?.orderOut(nil)
            miniPlayer?.showWindow(nil)
            miniPlayer?.window?.makeKeyAndOrderFront(nil)
        }
    }

    @objc func setSleepTimer(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        let timer = SleepTimer.shared
        // Pause and clear the on-screen banner when the timer fires (or EOF
        // hits with `.endOfFile` mode). The closure lives until cancel/re-arm.
        timer.onFire = { [weak self] in
            self?.windowController?.playerViewController.pauseForSleepTimer()
        }
        switch item.tag {
        case 0:
            timer.cancel()
            windowController?.playerViewController.showOSD(L("Sleep Timer cancelled"))
        case -1:
            timer.arm(.endOfFile)
            windowController?.playerViewController.showOSD(L("Sleep Timer: end of file"))
        default:
            timer.arm(.duration(minutes: item.tag))
            windowController?.playerViewController.showOSD(
                String(format: L("Sleep Timer set: %d minutes"), item.tag))
        }
    }
    @objc func jumpToTime(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = L("Jump to Time")
        alert.informativeText = L("Enter time (e.g. 1:30 or 90):")
        alert.addButton(withTitle: L("Jump"))
        alert.addButton(withTitle: L("Cancel"))
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.placeholderString = L("0:00")
        alert.accessoryView = input
        if alert.runModal() == .alertFirstButtonReturn {
            windowController?.playerViewController.seekToAbsoluteTime(parseTimeInput(input.stringValue))
        }
    }

    @objc func setSpeed(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        for mi in menu.items { mi.state = .off }
        item.state = .on
        let title = item.title.replacingOccurrences(of: "x", with: "")
        if let speed = Float(title) {
            windowController?.playerViewController.setSpeed(speed)
        }
    }

    @objc func toggleABRepeat(_ sender: Any?) {
        windowController?.playerViewController.toggleABLoop()
    }

    // MARK: - Audio Menu

    @objc func volumeUp(_ sender: Any?) {
        windowController?.playerViewController.adjustVolume(by: 0.05)
    }
    @objc func volumeDown(_ sender: Any?) {
        windowController?.playerViewController.adjustVolume(by: -0.05)
    }
    @objc func toggleMute(_ sender: Any?) {
        windowController?.playerViewController.toggleMute()
    }
    @objc func setEQPreset(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        // Clear only items that share our action (skip the separator)
        for mi in menu.items where mi.action == item.action { mi.state = .off }
        item.state = .on
        let presetIndex = item.tag
        UserDefaults.standard.set(presetIndex, forKey: Defaults.defaultEQPreset)
        windowController?.playerViewController.applyEQPreset(presetIndex)
        windowController?.playerViewController.showOSD(String(format: L("EQ: %@"), item.title))
    }

    @objc func selectOutputDevice(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        var deviceID = AudioDeviceID(item.tag)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
        windowController?.playerViewController.showOSD(String(format: L("Output: %@"), item.title))
    }

    @objc func audioSyncPull(_ sender: Any?) {
        let step = UserDefaults.standard.double(forKey: Defaults.audioDelayStep)
        windowController?.playerViewController.adjustAudioDelay(by: -(step > 0 ? step / 1000 : 0.1))
    }

    @objc func audioSyncPush(_ sender: Any?) {
        let step = UserDefaults.standard.double(forKey: Defaults.audioDelayStep)
        windowController?.playerViewController.adjustAudioDelay(by: step > 0 ? step / 1000 : 0.1)
    }

    @objc func audioSyncRevert(_ sender: Any?) {
        windowController?.playerViewController.resetAudioDelay()
    }

    // MARK: - Video Menu

    @objc func setAspectRatio(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        for mi in menu.items { mi.state = .off }
        item.state = .on
        windowController?.playerViewController.setAspectRatio(item.title)
    }

    @objc func setHalfSize(_ sender: Any?) {
        windowController?.playerViewController.setVideoWindowSize(scale: 0.5)
    }

    @objc func setOriginalSize(_ sender: Any?) {
        windowController?.playerViewController.setVideoWindowSize(scale: 1.0)
    }

    @objc func setDoubleSize(_ sender: Any?) {
        windowController?.playerViewController.setVideoWindowSize(scale: 2.0)
    }

    @objc func fitToScreen(_ sender: Any?) {
        windowController?.playerViewController.fitWindowToScreen()
    }

    @objc func fillScreen(_ sender: Any?) {
        windowController?.playerViewController.toggleFillScreen()
    }

    private var videoEQController: VideoEQPanelController?

    @objc func showVideoEQ(_ sender: Any?) {
        if videoEQController == nil {
            videoEQController = VideoEQPanelController()
        }
        videoEQController?.playerViewController = windowController?.playerViewController
        videoEQController?.showWindow(nil)
        videoEQController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func togglePiP(_ sender: Any?) {
        windowController?.playerViewController.togglePiP()
    }

    // MARK: - Window action wrappers
    //
    // AppKit auto-localizes the title of any menu item whose action is one
    // of its built-in window selectors (toggleFullScreen:, miniaturize:,
    // zoom:, close, etc.). The auto-localization reads from AppKit's OWN
    // bundle which follows the SYSTEM locale, not our app's AppleLanguages
    // override. So if the user has macOS in Chinese but switches our app
    // to English, "Enter Full Screen" still appears in Chinese — Chinese
    // strings bleeding into the English menu, which looks broken.
    //
    // Routing through our own selectors bypasses that auto-localization;
    // the title stays whatever we set via L() and respects our language.

    @objc func toggleFullScreenAction(_ sender: Any?) {
        windowController?.window?.toggleFullScreen(nil)
    }

    @objc func minimizeAction(_ sender: Any?) {
        windowController?.window?.miniaturize(nil)
    }

    @objc func zoomAction(_ sender: Any?) {
        windowController?.window?.zoom(nil)
    }

    @objc func closeWindowAction(_ sender: Any?) {
        NSApp.keyWindow?.performClose(nil)
    }

    @objc func rotateLeft(_ sender: Any?) {
        windowController?.playerViewController.rotateVideo(by: -90)
    }

    @objc func rotateRight(_ sender: Any?) {
        windowController?.playerViewController.rotateVideo(by: 90)
    }

    @objc func flipHorizontal(_ sender: Any?) {
        windowController?.playerViewController.flipVideo(horizontal: true)
    }

    @objc func flipVertical(_ sender: Any?) {
        windowController?.playerViewController.flipVideo(horizontal: false)
    }

    @objc func revertTransform(_ sender: Any?) {
        windowController?.playerViewController.revertVideoTransform()
    }

    @objc func setDeinterlace(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        for mi in menu.items { mi.state = .off }
        item.state = .on
        let mode = item.title == "Off" ? nil : item.title.lowercased()
        windowController?.playerViewController.vlcEngine?.setDeinterlace(mode: mode)
        windowController?.playerViewController.showOSD(String(format: L("Deinterlace: %@"), item.title))
    }

    @objc func setCrop(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        for mi in menu.items { mi.state = .off }
        item.state = .on
        let geometry = item.title == "Default" ? nil : item.title
        windowController?.playerViewController.vlcEngine?.setCropGeometry(geometry)
        windowController?.playerViewController.showOSD(String(format: L("Crop: %@"), item.title))
    }

    // MARK: - Subtitle Menu

    @objc func toggleSubtitles(_ sender: Any?) {
        windowController?.playerViewController.toggleSubtitleVisibility()
    }

    @objc func setSubtitlePosition(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        for mi in menu.items { mi.state = .off }
        item.state = .on
        windowController?.playerViewController.updateSubtitlePosition()
        windowController?.playerViewController.showOSD(String(format: L("Subtitle: %@"), item.title))
    }

    @objc func setSubtitleTextColor(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        for mi in menu.items { mi.state = .off }
        item.state = .on
        UserDefaults.standard.set(item.tag, forKey: Defaults.subtitleColor)
        windowController?.playerViewController.showOSD(String(format: L("Subtitle color: %@"), item.title))
    }

    @objc func setSubtitleOutlineThickness(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        for mi in menu.items { mi.state = .off }
        item.state = .on
        UserDefaults.standard.set(item.tag, forKey: Defaults.subtitleOutlineThickness)
        windowController?.playerViewController.showOSD(String(format: L("Outline: %@"), item.title))
    }

    @objc func setSubtitleBackgroundColor(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        for mi in menu.items { mi.state = .off }
        item.state = .on
        UserDefaults.standard.set(item.tag, forKey: Defaults.subtitleBackgroundColor)
        windowController?.playerViewController.showOSD(String(format: L("Background: %@"), item.title))
    }

    @objc func subtitleSyncPull(_ sender: Any?) {
        let step = UserDefaults.standard.double(forKey: Defaults.subtitleDelayStep)
        windowController?.playerViewController.adjustSubtitleDelay(by: -(step > 0 ? step : 0.1))
    }

    @objc func subtitleSyncPush(_ sender: Any?) {
        let step = UserDefaults.standard.double(forKey: Defaults.subtitleDelayStep)
        windowController?.playerViewController.adjustSubtitleDelay(by: step > 0 ? step : 0.1)
    }

    @objc func subtitleSyncRevert(_ sender: Any?) {
        windowController?.playerViewController.resetSubtitleDelay()
    }

    // MARK: - Playlist Menu

    @objc func setRepeatOff(_ sender: Any?) {
        windowController?.playerViewController.setRepeatMode(.off)
    }

    @objc func setRepeatOne(_ sender: Any?) {
        windowController?.playerViewController.setRepeatMode(.one)
    }

    @objc func setRepeatAll(_ sender: Any?) {
        windowController?.playerViewController.setRepeatMode(.all)
    }

    @objc func toggleShuffle(_ sender: Any?) {
        windowController?.playerViewController.toggleShuffle()
    }

    @objc func togglePlaylistPanel(_ sender: Any?) {
        windowController?.playerViewController.togglePlaylistPanel()
    }

    @objc func previousTrack(_ sender: Any?) {
        windowController?.playerViewController.playPreviousTrack()
    }

    @objc func nextTrack(_ sender: Any?) {
        windowController?.playerViewController.playNextTrack()
    }

    // MARK: - Cast Menu

    @objc func showAirPlay(_ sender: Any?) {
        guard let vc = windowController?.playerViewController else { return }
        vc.controlBarAirPlayRequested()
    }

    @objc func playOnExternalDisplay(_ sender: Any?) {
        windowController?.playerViewController.moveToExternalDisplay()
    }

    @objc func castToChromecast(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let device = item.representedObject as? (name: String, host: String, port: Int) else { return }
        guard let vc = windowController?.playerViewController else { return }
        guard let fileURL = vc.currentFileURL else {
            vc.showOSD(L("No file playing"))
            return
        }

        // Cast the URL the engine is actually decoding. For DV files this is
        // the remuxed temp .mp4 — sending the source MKV instead would feed
        // the receiver a container it can't decode (silent failure).
        let castURL = vc.playbackSourceURL ?? fileURL

        let castDevice = CastDevice(id: device.host, name: device.name, type: .chromecast, host: device.host, port: device.port)
        castingManager.delegate = self
        castingManager.connect(to: castDevice)
        castingManager.cast(fileURL: castURL, to: castDevice)
        vc.showOSD(String(format: L("Casting to %@…"), device.name), duration: 3.0)
    }

    @objc func showDLNA(_ sender: Any?) {
        castingManager.delegate = self
        castingManager.startDiscovery()
        windowController?.playerViewController.showOSD(L("Searching for DLNA devices…"), duration: 3.0)
    }

    @objc func disconnectCast(_ sender: Any?) {
        castingManager.disconnect()
        windowController?.playerViewController.showOSD(L("Disconnected"))
    }

    // MARK: - Window Menu

    private var inspectorController: MediaInspectorController?

    @objc func showInspector(_ sender: Any?) {
        if inspectorController == nil {
            inspectorController = MediaInspectorController()
        }
        if let url = windowController?.playerViewController.currentFileURL {
            inspectorController?.updateInfo(for: url)
        }
        inspectorController?.showWindow(nil)
        inspectorController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func toggleAlwaysOnTop(_ sender: Any?) {
        (windowController?.window as? PlayerWindow)?.toggleAlwaysOnTop()
    }

    // MARK: - About

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: NSApp.applicationIconImage,
            .applicationName: "Awesome Player",
            .applicationVersion: "1.0",
            .version: "1",
            .credits: NSAttributedString(
                string: "An awesome video player developed by 乖乖小狗\n\nxzm01234@gmail.com",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: {
                        let style = NSMutableParagraphStyle()
                        style.alignment = .center
                        return style
                    }(),
                ]
            ),
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "Copyright © 2025 Awesome Player. No damn rights reserved.",
        ])
    }

    // MARK: - Preferences

    private func parseTimeInput(_ input: String) -> Double {
        let parts = input.components(separatedBy: ":")
        switch parts.count {
        case 1: return Double(parts[0]) ?? 0
        case 2:
            return (Double(parts[0]) ?? 0) * 60 + (Double(parts[1]) ?? 0)
        case 3:
            return (Double(parts[0]) ?? 0) * 3600 + (Double(parts[1]) ?? 0) * 60 + (Double(parts[2]) ?? 0)
        default: return 0
        }
    }

    @objc func showPreferences(_ sender: Any?) {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController()
        }
        preferencesController?.showWindow(nil)
        preferencesController?.window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - CastingManagerDelegate

extension AppDelegate: CastingManagerDelegate {
    func castingManager(_ manager: CastingManager, didDiscoverDevice device: CastDevice) {
        windowController?.playerViewController.showOSD(String(format: L("Found: %@"), device.name))
    }

    func castingManager(_ manager: CastingManager, didRemoveDevice deviceId: String) {
    }

    func castingManager(_ manager: CastingManager, didChangeState state: CastState) {
        switch state {
        case .connected(let device):
            windowController?.playerViewController.showOSD(String(format: L("Connected to %@"), device.name))
        case .playing(let device):
            windowController?.playerViewController.showOSD(String(format: L("Casting to %@"), device.name))
        case .disconnected:
            windowController?.playerViewController.showOSD(L("Cast disconnected"))
        case .connecting:
            windowController?.playerViewController.showOSD(L("Connecting…"))
        }
    }

    func castingManager(_ manager: CastingManager, didUpdatePosition position: Double, duration: Double) {
    }

    func castingManager(_ manager: CastingManager, didFail message: String) {
        windowController?.playerViewController.showOSD(message, duration: 5.0)
    }
}
