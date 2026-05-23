import Cocoa
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: PlayerWindowController?
    private var preferencesController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Defaults.registerDefaults()
        MenuManager.setupMainMenu()

        windowController = PlayerWindowController()
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        windowController?.openFile(url: url)
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            windowController?.openFile(url: url)
            break
        }
        sender.reply(toOpenOrPrint: .success)
    }

    // MARK: - File Menu

    @IBAction func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.windowController?.openFile(url: url)
        }
    }

    @objc func openURL(_ sender: Any?) {}
    @objc func addSubtitleFile(_ sender: Any?) {}
    @objc func saveScreenshot(_ sender: Any?) {}

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
    @objc func jumpToTime(_ sender: Any?) {}
    @objc func setSpeed(_ sender: Any?) {}
    @objc func toggleABRepeat(_ sender: Any?) {}

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
    @objc func showAudioPanel(_ sender: Any?) {}
    @objc func togglePassthrough(_ sender: Any?) {}
    @objc func setEQPreset(_ sender: Any?) {}
    @objc func selectOutputDevice(_ sender: Any?) {}
    @objc func audioSyncPull(_ sender: Any?) {}
    @objc func audioSyncPush(_ sender: Any?) {}
    @objc func audioSyncRevert(_ sender: Any?) {}

    // MARK: - Video Menu

    @objc func setAspectRatio(_ sender: Any?) {}
    @objc func setHalfSize(_ sender: Any?) {}
    @objc func setOriginalSize(_ sender: Any?) {}
    @objc func setDoubleSize(_ sender: Any?) {}
    @objc func fitToScreen(_ sender: Any?) {}
    @objc func fillScreen(_ sender: Any?) {}
    @objc func showVideoEQ(_ sender: Any?) {}
    @objc func togglePiP(_ sender: Any?) {}
    @objc func rotateLeft(_ sender: Any?) {}
    @objc func rotateRight(_ sender: Any?) {}
    @objc func flipHorizontal(_ sender: Any?) {}
    @objc func flipVertical(_ sender: Any?) {}
    @objc func revertTransform(_ sender: Any?) {}

    // MARK: - Subtitle Menu

    @objc func toggleSubtitles(_ sender: Any?) {}
    @objc func setSubtitlePosition(_ sender: Any?) {}
    @objc func subtitleSyncPull(_ sender: Any?) {}
    @objc func subtitleSyncPush(_ sender: Any?) {}
    @objc func subtitleSyncRevert(_ sender: Any?) {}

    // MARK: - Playlist Menu

    @objc func setRepeatOff(_ sender: Any?) {}
    @objc func setRepeatOne(_ sender: Any?) {}
    @objc func setRepeatAll(_ sender: Any?) {}
    @objc func toggleShuffle(_ sender: Any?) {}
    @objc func previousTrack(_ sender: Any?) {}
    @objc func nextTrack(_ sender: Any?) {}

    // MARK: - Cast Menu

    @objc func showAirPlay(_ sender: Any?) {}
    @objc func showChromecast(_ sender: Any?) {}
    @objc func showDLNA(_ sender: Any?) {}
    @objc func disconnectCast(_ sender: Any?) {}

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

    @objc func showPreferences(_ sender: Any?) {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController()
        }
        preferencesController?.showWindow(nil)
        preferencesController?.window?.makeKeyAndOrderFront(nil)
    }
}
