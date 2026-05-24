import Cocoa
import AVFoundation
import CoreAudio
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: PlayerWindowController?
    private var preferencesController: PreferencesWindowController?
    private let castingManager = CastingManager()
    let nowPlayingController = NowPlayingController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Defaults.registerDefaults()
        applyTheme()
        MenuManager.setupMainMenu()

        windowController = PlayerWindowController()
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)

        nowPlayingController.playerViewController = windowController?.playerViewController
        nowPlayingController.setup()

        NSApp.activate(ignoringOtherApps: true)

        // Watch for theme changes from preferences
        UserDefaults.standard.addObserver(self, forKeyPath: Defaults.theme, options: .new, context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == Defaults.theme {
            applyTheme()
        }
    }

    private func applyTheme() {
        let themeIndex = UserDefaults.standard.integer(forKey: Defaults.theme)
        switch themeIndex {
        case 1: NSApp.appearance = NSAppearance(named: .darkAqua)
        case 2: NSApp.appearance = NSAppearance(named: .aqua)
        default: NSApp.appearance = nil // system
        }
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

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            RecentDocumentsMenuDelegate.addRecentFile(url)
            windowController?.openFile(url: url)
            break
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
        let alert = NSAlert()
        alert.messageText = "Open URL"
        alert.informativeText = "Enter a media URL or YouTube/web link:"
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        input.placeholderString = "https://example.com/video.mp4 or YouTube URL"
        alert.accessoryView = input
        if alert.runModal() == .alertFirstButtonReturn,
           !input.stringValue.isEmpty {
            let urlString = input.stringValue
            if let url = URL(string: urlString), isDirectMediaURL(urlString) {
                windowController?.openFile(url: url)
            } else {
                resolveWithYTDLP(urlString)
            }
        }
    }

    private func isDirectMediaURL(_ url: String) -> Bool {
        let mediaExts = ["mp4", "mkv", "avi", "mov", "m4v", "webm", "flv", "wmv", "mpg", "mpeg", "m4a", "mp3", "flac", "ogg"]
        let lower = url.lowercased()
        return mediaExts.contains(where: { lower.hasSuffix(".\($0)") })
    }

    private func resolveWithYTDLP(_ urlString: String) {
        let ytdlpPaths = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
        guard let ytdlp = ytdlpPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            windowController?.playerViewController.showOSD("yt-dlp not found — install via: brew install yt-dlp", duration: 5.0)
            return
        }
        windowController?.playerViewController.showOSD("Resolving URL…", duration: 10.0)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytdlp)
            process.arguments = ["--get-url", "-f", "best", urlString]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty,
                   let resolvedURL = URL(string: output.components(separatedBy: "\n").first ?? "") {
                    DispatchQueue.main.async {
                        self?.windowController?.openFile(url: resolvedURL)
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.windowController?.playerViewController.showOSD("Failed to resolve URL")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.windowController?.playerViewController.showOSD("yt-dlp error: \(error.localizedDescription)")
                }
            }
        }
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
    @objc func jumpToTime(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Jump to Time"
        alert.informativeText = "Enter time (e.g. 1:30 or 90):"
        alert.addButton(withTitle: "Jump")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.placeholderString = "0:00"
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
    @objc func showAudioPanel(_ sender: Any?) {
        windowController?.playerViewController.showOSD("Audio panel")
    }

    @objc func togglePassthrough(_ sender: Any?) {
        windowController?.playerViewController.togglePassthrough()
    }

    @objc func setEQPreset(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        for mi in menu.items { mi.state = .off }
        item.state = .on
        let index = menu.index(of: item)
        UserDefaults.standard.set(index, forKey: Defaults.defaultEQPreset)
        windowController?.playerViewController.applyEQPreset(index)
        windowController?.playerViewController.showOSD("EQ: \(item.title)")
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
        windowController?.playerViewController.showOSD("Output: \(item.title)")
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

    @objc func showVideoEQ(_ sender: Any?) {
        windowController?.playerViewController.showOSD("Video equalizer")
    }

    @objc func togglePiP(_ sender: Any?) {
        windowController?.playerViewController.togglePiP()
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

    // MARK: - Subtitle Menu

    @objc func toggleSubtitles(_ sender: Any?) {
        windowController?.playerViewController.toggleSubtitleVisibility()
    }

    @objc func setSubtitlePosition(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        for mi in menu.items { mi.state = .off }
        item.state = .on
        windowController?.playerViewController.showOSD("Subtitle: \(item.title)")
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
        // AVRoutePickerView on macOS only routes audio — for video, the user
        // needs Screen Mirroring from Control Center or an external display.
        // Trigger the picker for audio, then open Screen Mirroring if video
        // doesn't activate.
        windowController?.playerViewController.showAirPlayPicker()

        // Also open the Displays settings so the user can add the TV as a display
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let vc = self?.windowController?.playerViewController,
                  !(vc.playerEngine?.player?.isExternalPlaybackActive ?? false) else { return }
            vc.showOSD("Tip: Use Control Center > Screen Mirroring to show video on TV", duration: 5.0)
        }
    }

    @objc func playOnExternalDisplay(_ sender: Any?) {
        windowController?.playerViewController.moveToExternalDisplay()
    }

    @objc func castToChromecast(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let device = item.representedObject as? (name: String, host: String, port: Int) else { return }
        guard let vc = windowController?.playerViewController else { return }
        guard let fileURL = vc.currentFileURL else {
            vc.showOSD("No file playing")
            return
        }

        // Use the currently playing file — for remuxed MKVs, use the temp MP4
        let castURL: URL
        if let currentItem = vc.playerEngine?.player?.currentItem,
           let asset = currentItem.asset as? AVURLAsset {
            castURL = asset.url
        } else {
            castURL = fileURL
        }

        let castDevice = CastDevice(id: device.host, name: device.name, type: .chromecast, host: device.host, port: device.port)
        castingManager.delegate = self
        castingManager.connect(to: castDevice)
        castingManager.cast(fileURL: castURL, to: castDevice)
        vc.showOSD("Casting to \(device.name)…", duration: 3.0)
    }

    @objc func showChromecast(_ sender: Any?) {
        castingManager.delegate = self
        castingManager.startDiscovery()
        windowController?.playerViewController.showOSD("Searching for Chromecast devices…", duration: 3.0)
    }

    @objc func showDLNA(_ sender: Any?) {
        castingManager.delegate = self
        castingManager.startDiscovery()
        windowController?.playerViewController.showOSD("Searching for DLNA devices…", duration: 3.0)
    }

    @objc func disconnectCast(_ sender: Any?) {
        castingManager.disconnect()
        windowController?.playerViewController.showOSD("Disconnected")
    }

    // MARK: - Window Menu

    @objc func toggleAlwaysOnTop(_ sender: Any?) {
        (windowController?.window as? PlayerWindow)?.toggleAlwaysOnTop()
    }

    // MARK: - About

    @objc func showAbout(_ sender: Any?) {
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
        let catImage = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "Awesome Player")?.withSymbolConfiguration(iconConfig)

        let icon: NSImage
        if let cat = catImage {
            let rendered = NSImage(size: NSSize(width: 128, height: 128))
            rendered.lockFocus()
            NSColor(calibratedRed: 0.55, green: 0.65, blue: 0.95, alpha: 1).setFill()
            let rect = NSRect(x: 0, y: 0, width: 128, height: 128)
            let bg = NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28)
            bg.fill()
            cat.draw(in: NSRect(x: 20, y: 20, width: 88, height: 88),
                     from: .zero, operation: .sourceOver, fraction: 1.0)
            rendered.unlockFocus()
            icon = rendered
        } else {
            icon = NSApp.applicationIconImage
        }

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: icon,
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
        windowController?.playerViewController.showOSD("Found: \(device.name)")
    }

    func castingManager(_ manager: CastingManager, didRemoveDevice deviceId: String) {
    }

    func castingManager(_ manager: CastingManager, didChangeState state: CastState) {
        switch state {
        case .connected(let device):
            windowController?.playerViewController.showOSD("Connected to \(device.name)")
        case .playing(let device):
            windowController?.playerViewController.showOSD("Casting to \(device.name)")
        case .disconnected:
            windowController?.playerViewController.showOSD("Cast disconnected")
        case .connecting:
            windowController?.playerViewController.showOSD("Connecting…")
        }
    }

    func castingManager(_ manager: CastingManager, didUpdatePosition position: Double, duration: Double) {
    }
}
