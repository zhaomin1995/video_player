import Cocoa
import AVFoundation
import CoreAudio
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: PlayerWindowController?
    private var preferencesController: PreferencesWindowController?
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

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.playerViewController.saveCurrentPosition()
        UserDefaults.standard.removeObserver(self, forKeyPath: Defaults.theme)
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

    private func findYTDLP() -> String? {
        let bundledPath = Bundle.main.resourceURL?.appendingPathComponent("yt-dlp/yt-dlp_macos").path
        let searchPaths = [bundledPath, "/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"].compactMap { $0 }
        return searchPaths.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    private func runYTDLP(_ ytdlp: String, arguments: [String]) -> (stdout: String, stderr: String, exitCode: Int32)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlp)
        process.currentDirectoryURL = URL(fileURLWithPath: ytdlp).deletingLastPathComponent()
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do { try process.run() } catch { return nil }

        var errData = Data()
        let errThread = Thread { errData = errPipe.fileHandleForReading.readDataToEndOfFile() }
        errThread.start()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        while !errThread.isFinished { Thread.sleep(forTimeInterval: 0.01) }

        return (
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }

    private struct YTDLPFormat {
        let formatID: String
        let height: Int
        let ext: String
        let hasAudio: Bool
    }

    private func resolveWithYTDLP(_ urlString: String) {
        guard let ytdlp = findYTDLP() else {
            windowController?.playerViewController.showOSD("yt-dlp not found", duration: 5.0)
            return
        }
        windowController?.playerViewController.showOSD("Fetching formats…", duration: 60.0)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let result = self?.runYTDLP(ytdlp, arguments: ["-j", "--no-warnings", "--no-playlist", urlString]),
                  result.exitCode == 0,
                  let jsonData = result.stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let formats = json["formats"] as? [[String: Any]] else {
                DispatchQueue.main.async {
                    self?.windowController?.playerViewController.showOSD("Failed to fetch video info", duration: 5.0)
                }
                return
            }

            let title = json["title"] as? String ?? urlString

            var videoFormats: [YTDLPFormat] = []
            var seenHeights = Set<Int>()
            for fmt in formats {
                guard let fid = fmt["format_id"] as? String,
                      let height = fmt["height"] as? Int, height > 0,
                      let vc = fmt["vcodec"] as? String, vc != "none",
                      let ext = fmt["ext"] as? String else { continue }
                let hasAudio = ((fmt["acodec"] as? String) ?? "none") != "none"
                if seenHeights.contains(height) {
                    if let idx = videoFormats.firstIndex(where: { $0.height == height }) {
                        let existing = videoFormats[idx]
                        if ext == "mp4" && existing.ext != "mp4" {
                            videoFormats[idx] = YTDLPFormat(formatID: fid, height: height, ext: ext, hasAudio: hasAudio)
                        }
                    }
                } else {
                    seenHeights.insert(height)
                    videoFormats.append(YTDLPFormat(formatID: fid, height: height, ext: ext, hasAudio: hasAudio))
                }
            }
            videoFormats.sort { $0.height > $1.height }

            guard !videoFormats.isEmpty else {
                DispatchQueue.main.async {
                    self?.windowController?.playerViewController.showOSD("No video formats found", duration: 5.0)
                }
                return
            }

            DispatchQueue.main.async {
                self?.windowController?.playerViewController.showOSD("")
                self?.showResolutionPicker(title: title, formats: videoFormats, ytdlp: ytdlp, urlString: urlString)
            }
        }
    }

    private func showResolutionPicker(title: String, formats: [YTDLPFormat], ytdlp: String, urlString: String) {
        let alert = NSAlert()
        alert.messageText = "Select Resolution"
        alert.informativeText = title
        alert.addButton(withTitle: "Play")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 28), pullsDown: false)
        for fmt in formats {
            let suffix = fmt.hasAudio ? "" : " (video+audio merge)"
            popup.addItem(withTitle: "\(fmt.height)p\(suffix)")
        }
        popup.selectItem(at: 0)
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let chosen = formats[popup.indexOfSelectedItem]
        windowController?.playerViewController.showOSD("Loading \(chosen.height)p…", duration: 60.0)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var formatSpec = chosen.formatID
            if !chosen.hasAudio {
                formatSpec = "\(chosen.formatID)+bestaudio[ext=m4a]/\(chosen.formatID)+bestaudio"
            }
            guard let result = self?.runYTDLP(ytdlp, arguments: ["--get-url", "-f", formatSpec, "--no-warnings", "--no-playlist", urlString]),
                  result.exitCode == 0 else {
                DispatchQueue.main.async {
                    self?.windowController?.playerViewController.showOSD("Failed to get stream URL", duration: 5.0)
                }
                return
            }

            let urls = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").compactMap { URL(string: $0) }
            guard let videoURL = urls.first else {
                DispatchQueue.main.async {
                    self?.windowController?.playerViewController.showOSD("Failed to get stream URL", duration: 5.0)
                }
                return
            }

            let audioURL = urls.count > 1 ? urls[1] : nil

            DispatchQueue.main.async {
                if audioURL != nil {
                    self?.openStreamWithVLC(videoURL: videoURL, audioURL: audioURL, title: title)
                } else {
                    self?.windowController?.openFile(url: videoURL)
                }
            }
        }
    }

    private func openStreamWithVLC(videoURL: URL, audioURL: URL?, title: String) {
        guard let vc = windowController?.playerViewController else { return }
        vc.openStream(videoURL: videoURL, audioURL: audioURL)
        windowController?.titleBarView.setTitle(title)
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
    @objc func setEQPreset(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        // Clear only items that share our action (skip the separator)
        for mi in menu.items where mi.action == item.action { mi.state = .off }
        item.state = .on
        let presetIndex = item.tag
        UserDefaults.standard.set(presetIndex, forKey: Defaults.defaultEQPreset)
        windowController?.playerViewController.applyEQPreset(presetIndex)
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
        windowController?.playerViewController.showOSD("Deinterlace: \(item.title)")
    }

    @objc func setCrop(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        for mi in menu.items { mi.state = .off }
        item.state = .on
        let geometry = item.title == "Default" ? nil : item.title
        windowController?.playerViewController.vlcEngine?.setCropGeometry(geometry)
        windowController?.playerViewController.showOSD("Crop: \(item.title)")
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
        windowController?.playerViewController.showOSD("Subtitle: \(item.title)")
    }

    @objc func setSubtitleTextColor(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        for mi in menu.items { mi.state = .off }
        item.state = .on
        UserDefaults.standard.set(item.tag, forKey: Defaults.subtitleColor)
        windowController?.playerViewController.showOSD("Subtitle color: \(item.title)")
    }

    @objc func setSubtitleOutlineThickness(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        for mi in menu.items { mi.state = .off }
        item.state = .on
        UserDefaults.standard.set(item.tag, forKey: Defaults.subtitleOutlineThickness)
        windowController?.playerViewController.showOSD("Outline: \(item.title)")
    }

    @objc func setSubtitleBackgroundColor(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let menu = item.menu else { return }
        for mi in menu.items { mi.state = .off }
        item.state = .on
        UserDefaults.standard.set(item.tag, forKey: Defaults.subtitleBackgroundColor)
        windowController?.playerViewController.showOSD("Background: \(item.title)")
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

    func castingManager(_ manager: CastingManager, didFail message: String) {
        windowController?.playerViewController.showOSD(message, duration: 5.0)
    }
}
