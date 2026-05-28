import Cocoa
import CoreAudio

class AudioDeviceMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = AudioDeviceMenuDelegate()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize) == noErr else { return }

        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &deviceIDs) == noErr else { return }

        // Get default output device
        var defaultDevice: AudioDeviceID = 0
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, &defaultSize, &defaultDevice)

        for deviceID in deviceIDs {
            // Filter out virtual and aggregate devices (e.g. ZoomAudioDevice, BlackHole)
            var transportType: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(deviceID, &transportAddress, 0, nil, &transportSize, &transportType) == noErr {
                if transportType == kAudioDeviceTransportTypeVirtual ||
                   transportType == kAudioDeviceTransportTypeAggregate {
                    continue
                }
            }

            // Check if device has output streams
            var streamSize: UInt32 = 0
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize) == noErr, streamSize > 0 else { continue }

            // Get device name
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameUnmanaged: Unmanaged<CFString>?
            guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameUnmanaged) == noErr,
                  let name = nameUnmanaged?.takeUnretainedValue() as String? else { continue }

            let item = NSMenuItem(title: name, action: #selector(AppDelegate.selectOutputDevice(_:)), keyEquivalent: "")
            item.tag = Int(deviceID)
            item.target = nil
            if deviceID == defaultDevice {
                item.state = .on
            }
            menu.addItem(item)
        }

        if menu.items.isEmpty {
            let none = NSMenuItem(title: L("No devices found"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
    }
}

// AirPlayMenuDelegate moved to UI/Menu/Delegates/AirPlayMenuDelegate.swift

// ChromecastMenuDelegate moved to UI/Menu/Delegates/ChromecastMenuDelegate.swift

/// Populates Open Recent menu from a manually managed list in UserDefaults.
class RecentDocumentsMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = RecentDocumentsMenuDelegate()
    private static let key = "AwesomePlayer_RecentFiles"
    private static let maxRecent = 10

    static func addRecentFile(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        if paths.count > maxRecent { paths = Array(paths.prefix(maxRecent)) }
        UserDefaults.standard.set(paths, forKey: key)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let paths = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        if paths.isEmpty {
            let none = NSMenuItem(title: L("(No Recent Files)"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for path in paths {
                let url = URL(fileURLWithPath: path)
                let item = menu.addItem(withTitle: url.lastPathComponent, action: #selector(openRecentFile(_:)), keyEquivalent: "")
                item.representedObject = url
                item.target = self
            }
        }
        menu.addItem(.separator())
        let clearItem = menu.addItem(withTitle: L("Clear Menu"), action: #selector(clearRecent(_:)), keyEquivalent: "")
        clearItem.target = self
    }

    @objc private func openRecentFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let wc = NSApp.mainWindow?.windowController as? PlayerWindowController else { return }
        wc.openFile(url: url)
    }

    @objc private func clearRecent(_ sender: NSMenuItem) {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

// TrackMenuDelegate moved to UI/Menu/Delegates/TrackMenuDelegate.swift

class ChapterMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = ChapterMenuDelegate()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let wc = NSApp.mainWindow?.windowController as? PlayerWindowController else {
            addNoneItem(to: menu)
            return
        }
        let chapters = wc.playerViewController.chapters
        if chapters.isEmpty {
            addNoneItem(to: menu)
            return
        }

        let current = wc.playerViewController.playerEngine?.currentTime ?? wc.playerViewController.vlcEngine?.currentTime ?? 0

        for (i, chapter) in chapters.enumerated() {
            let title = chapter["title"] as? String ?? "Chapter \(i + 1)"
            let startTime = chapter["startTime"] as? Double ?? 0
            let timeStr = formatTime(startTime)
            let item = menu.addItem(withTitle: "\(title)  (\(timeStr))", action: #selector(chapterSelected(_:)), keyEquivalent: "")
            item.tag = i
            item.target = self

            let endTime = chapter["endTime"] as? Double ?? Double.greatestFiniteMagnitude
            if current >= startTime && current < endTime {
                item.state = .on
            }
        }
    }

    @objc private func chapterSelected(_ sender: NSMenuItem) {
        guard let wc = NSApp.mainWindow?.windowController as? PlayerWindowController else { return }
        wc.playerViewController.seekToChapter(at: sender.tag)
    }

    private func addNoneItem(to menu: NSMenu) {
        let item = NSMenuItem(title: L("(No Chapters)"), action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

/// Rebuilt on every open so the "remaining 12:34" countdown reflects current
/// state. The presets match what podcast/audiobook apps converge on; "End of
/// File" is the most-requested option for video.
class SleepTimerMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = SleepTimerMenuDelegate()
    private static let presetMinutes = [15, 30, 45, 60, 90]

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let timer = SleepTimer.shared

        let offTitle: String
        switch timer.mode {
        case .off:
            offTitle = L("Off")
        case .duration:
            let remaining = timer.remainingSeconds
            let m = remaining / 60
            let s = remaining % 60
            offTitle = String(format: L("Off  (%d:%02d remaining)"), m, s)
        case .endOfFile:
            offTitle = L("Off  (waiting for end of file)")
        }
        let off = menu.addItem(withTitle: offTitle, action: #selector(AppDelegate.setSleepTimer(_:)), keyEquivalent: "")
        off.tag = 0
        if timer.mode == .off { off.state = .on }

        menu.addItem(.separator())

        for mins in Self.presetMinutes {
            let item = menu.addItem(
                withTitle: String(format: L("%d minutes"), mins),
                action: #selector(AppDelegate.setSleepTimer(_:)),
                keyEquivalent: "")
            item.tag = mins
            if case .duration(let armed) = timer.mode, armed == mins { item.state = .on }
        }

        menu.addItem(.separator())
        let eof = menu.addItem(withTitle: L("End of File"),
                               action: #selector(AppDelegate.setSleepTimer(_:)),
                               keyEquivalent: "")
        eof.tag = -1
        if timer.mode == .endOfFile { eof.state = .on }
    }
}

/// VLC-style playback speed slider that lives inline in the Playback menu.
/// Uses a log2 scale so 1.0× sits dead center between 0.25× and 4.0×.
class PlaybackSpeedSliderView: NSView {
    static let shared = PlaybackSpeedSliderView()

    private let titleLabel = NSTextField(labelWithString: L("Playback Speed"))
    private let valueLabel = NSTextField(labelWithString: "1.00x")
    private let slider = NSSlider()
    private let slowerLabel = NSTextField(labelWithString: L("Slower"))
    private let normalLabel = NSTextField(labelWithString: L("Normal"))
    private let fasterLabel = NSTextField(labelWithString: L("Faster"))

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 64))
        setupViews()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        titleLabel.font = .systemFont(ofSize: 13)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        valueLabel.alignment = .right
        for l in [slowerLabel, normalLabel, fasterLabel] {
            l.font = .systemFont(ofSize: 10)
            l.textColor = .secondaryLabelColor
        }
        normalLabel.alignment = .center

        // Log2 scale: slider ∈ [-2, 2] → speed ∈ [0.25, 4.0], 0 → 1.0× centered
        slider.minValue = -2.0
        slider.maxValue = 2.0
        slider.doubleValue = 0.0
        slider.numberOfTickMarks = 17
        slider.tickMarkPosition = .below
        slider.allowsTickMarkValuesOnly = false
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true

        for v in [titleLabel, valueLabel, slider, slowerLabel, normalLabel, fasterLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            slowerLabel.leadingAnchor.constraint(equalTo: slider.leadingAnchor),
            slowerLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: -2),
            slowerLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
            normalLabel.centerXAnchor.constraint(equalTo: slider.centerXAnchor),
            normalLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: -2),
            fasterLabel.trailingAnchor.constraint(equalTo: slider.trailingAnchor),
            fasterLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: -2),
        ])
    }

    @objc private func sliderChanged() {
        let speed = Float(pow(2.0, slider.doubleValue))
        valueLabel.stringValue = String(format: "%.2fx", speed)
        guard let wc = NSApp.mainWindow?.windowController as? PlayerWindowController else { return }
        wc.playerViewController.setSpeed(speed)
    }

    /// Sync the slider to the live playback rate. Called from PlaybackMenuDelegate
    /// on menu-open so the slider reflects state changed via presets or keyboard.
    func refreshFromPlayer() {
        let speed: Float
        if let wc = NSApp.mainWindow?.windowController as? PlayerWindowController {
            let vc = wc.playerViewController
            speed = vc.playerEngine?.rate ?? vc.vlcEngine?.rate ?? 1.0
        } else {
            speed = 1.0
        }
        let clamped = max(0.25, min(4.0, speed))
        slider.doubleValue = log2(Double(clamped))
        valueLabel.stringValue = String(format: "%.2fx", clamped)
    }
}

class PlaybackMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = PlaybackMenuDelegate()
    func menuWillOpen(_ menu: NSMenu) {
        PlaybackSpeedSliderView.shared.refreshFromPlayer()
    }
}

/// VLC-style inline opacity slider for subtitle background. 0% → fully
/// transparent, 100% → fully opaque (color chosen via Background Color submenu).
class SubtitleOpacitySliderView: NSView {
    static let shared = SubtitleOpacitySliderView()

    private let titleLabel = NSTextField(labelWithString: L("Background Opacity"))
    private let slider = NSSlider()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 48))
        setupViews()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        titleLabel.font = .systemFont(ofSize: 13)

        slider.minValue = 0.0
        slider.maxValue = 1.0
        slider.doubleValue = UserDefaults.standard.double(forKey: Defaults.subtitleBackgroundOpacity)
        slider.numberOfTickMarks = 21
        slider.tickMarkPosition = .below
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true

        for v in [titleLabel, slider] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            slider.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
        ])
    }

    @objc private func sliderChanged() {
        UserDefaults.standard.set(slider.doubleValue, forKey: Defaults.subtitleBackgroundOpacity)
    }

    func refreshFromDefaults() {
        slider.doubleValue = UserDefaults.standard.double(forKey: Defaults.subtitleBackgroundOpacity)
    }
}

class SubtitleMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = SubtitleMenuDelegate()
    func menuWillOpen(_ menu: NSMenu) {
        SubtitleOpacitySliderView.shared.refreshFromDefaults()
    }
}

/// Strips the AppKit-injected items (AutoFill, Start Dictation, Emoji &
/// Symbols) that macOS automatically adds to any menu it detects as the
/// "Edit menu" (i.e. any menu containing cut:/copy:/paste: items). None of
/// those three items make sense for a video player — the dialog text fields
/// only hold URLs and timecodes. Matches by stable selector name where
/// possible, and by localized title substring for AutoFill (whose parent
/// item has no public selector we can match against).
class EditMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = EditMenuDelegate()

    /// Public AppKit selectors AppKit auto-attaches to the injected items.
    /// Matching by selector survives any locale change.
    private let unwantedSelectorNames: Set<String> = [
        "orderFrontCharacterPalette:",   // Emoji & Symbols (⌃⌘Space)
        "startDictation:",                // Start Dictation
    ]

    /// AutoFill's parent item has action == nil (it's a submenu container)
    /// so selector matching doesn't reach it. Fall back to localized title
    /// substrings across our supported locales.
    private let autoFillTitleSubstrings: [String] = [
        "AutoFill", "Autofill",
        "自动填充", "自動填寫", "自動填入",   // zh-Hans, zh-Hant, yue alt
        "自動入力",                            // ja
        "자동 완성", "자동완성",               // ko
        "Rellenar", "Autorrelleno",            // es
        "Remplir", "Saisie",                   // fr
        "Ausfüllen", "Autoausfüllen",          // de
        "Preencher", "Preenchimento",          // pt-BR
        "Автозаполнение",                      // ru
    ]

    func menuNeedsUpdate(_ menu: NSMenu) { strip(menu) }
    func menuWillOpen(_ menu: NSMenu) { strip(menu) }

    private func strip(_ menu: NSMenu) {
        for item in menu.items.reversed() {
            if let action = item.action,
               unwantedSelectorNames.contains(NSStringFromSelector(action)) {
                menu.removeItem(item)
                continue
            }
            if item.submenu != nil,
               autoFillTitleSubstrings.contains(where: { item.title.localizedCaseInsensitiveContains($0) }) {
                menu.removeItem(item)
            }
        }
        // Drop any orphaned trailing separator left behind by the removals
        while let last = menu.items.last, last.isSeparatorItem {
            menu.removeItem(last)
        }
    }
}

class MenuManager {
    static func setupMainMenu() {
        let mainMenu = NSMenu()

        mainMenu.addItem(createAppMenu())
        mainMenu.addItem(createFileMenu())
        mainMenu.addItem(createEditMenu())
        mainMenu.addItem(createPlaybackMenu())
        mainMenu.addItem(createAudioMenu())
        mainMenu.addItem(createVideoMenu())
        mainMenu.addItem(createSubtitleMenu())
        mainMenu.addItem(createPlaylistMenu())
        mainMenu.addItem(createCastMenu())
        mainMenu.addItem(createWindowMenu())
        mainMenu.addItem(createHelpMenu())

        NSApplication.shared.mainMenu = mainMenu
    }

    private static func createAppMenu() -> NSMenuItem {
        let menuItem = NSMenuItem()
        let menu = NSMenu()

        menu.addItem(withTitle: L("About Awesome Player"), action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Check for Updates…"), action: #selector(AppDelegate.checkForUpdatesAction(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Preferences…"), action: #selector(AppDelegate.showPreferences(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        let services = NSMenuItem(title: L("Services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: L("Services"))
        services.submenu = servicesMenu
        NSApplication.shared.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Hide Awesome Player"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: L("Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: L("Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Quit Awesome Player"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createEditMenu() -> NSMenuItem {
        // Undo / Redo were dropped: nothing in the player has an undo stack,
        // and dialog text fields are too short for ⌘Z to be meaningful. Cut /
        // Copy / Paste / Select All stay because their keyboard shortcuts
        // are routed via the main menu, so without them users can't paste
        // into the Open URL / Jump to Time / Convert/Stream text fields.
        //
        // EditMenuDelegate strips the AppKit-injected AutoFill / Start
        // Dictation / Emoji & Symbols items that macOS auto-attaches to any
        // menu containing cut:/copy:/paste: items — none make sense here.
        let menuItem = NSMenuItem(title: L("Edit"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: L("Edit"))
        menu.delegate = EditMenuDelegate.shared

        menu.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createFileMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: L("File"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: L("File"))

        menu.addItem(withTitle: L("Open File…"), action: #selector(AppDelegate.openFileAction(_:)), keyEquivalent: "o")
        menu.addItem(withTitle: L("Open URL…"), action: #selector(AppDelegate.openURL(_:)), keyEquivalent: "u")

        let recentItem = NSMenuItem(title: L("Open Recent"), action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: L("Open Recent"))
        recentMenu.delegate = RecentDocumentsMenuDelegate.shared
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: L("Add Subtitle File…"), action: #selector(AppDelegate.addSubtitleFile(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Save Screenshot"), action: #selector(AppDelegate.saveScreenshot(_:)), keyEquivalent: "s")
        menu.addItem(.separator())
        let convertItem = menu.addItem(withTitle: L("Convert / Stream…"),
            action: #selector(AppDelegate.showConvertStream(_:)), keyEquivalent: "s")
        convertItem.keyEquivalentModifierMask = [.shift, .command]
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Close"), action: #selector(AppDelegate.closeWindowAction(_:)), keyEquivalent: "w")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createPlaybackMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: L("Playback"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: L("Playback"))
        // Delegate refreshes the speed slider value from live playback rate on open
        menu.delegate = PlaybackMenuDelegate.shared

        menu.addItem(withTitle: L("Play / Pause"), action: #selector(AppDelegate.togglePlayPause(_:)), keyEquivalent: " ")

        menu.addItem(.separator())
        let seekFwd = menu.addItem(withTitle: L("Seek Forward 5s"), action: #selector(AppDelegate.seekForward5(_:)), keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)))
        seekFwd.keyEquivalentModifierMask = []
        let seekBwd = menu.addItem(withTitle: L("Seek Backward 5s"), action: #selector(AppDelegate.seekBackward5(_:)), keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        seekBwd.keyEquivalentModifierMask = []

        menu.addItem(.separator())
        let frameFwd = menu.addItem(withTitle: L("Step Forward One Frame"),
            action: #selector(AppDelegate.stepFrameForward(_:)), keyEquivalent: ".")
        frameFwd.keyEquivalentModifierMask = []
        let frameBwd = menu.addItem(withTitle: L("Step Backward One Frame"),
            action: #selector(AppDelegate.stepFrameBackward(_:)), keyEquivalent: ",")
        frameBwd.keyEquivalentModifierMask = []

        menu.addItem(.separator())
        menu.addItem(withTitle: L("Jump to Time…"), action: #selector(AppDelegate.jumpToTime(_:)), keyEquivalent: "j")

        menu.addItem(.separator())
        // VLC-style inline speed slider (continuous 0.25× to 4×, log scale)
        let speedSliderItem = NSMenuItem()
        speedSliderItem.view = PlaybackSpeedSliderView.shared
        menu.addItem(speedSliderItem)

        // Keep discrete presets for users who prefer click-to-set
        let speedMenu = NSMenuItem(title: L("Speed Presets"), action: nil, keyEquivalent: "")
        let speedSubmenu = NSMenu(title: L("Speed Presets"))
        for speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
            let item = speedSubmenu.addItem(withTitle: String(format: "%.2gx", speed), action: #selector(AppDelegate.setSpeed(_:)), keyEquivalent: "")
            if speed == 1.0 { item.state = .on }
        }
        speedMenu.submenu = speedSubmenu
        menu.addItem(speedMenu)

        menu.addItem(.separator())
        menu.addItem(withTitle: L("A-B Repeat"), action: #selector(AppDelegate.toggleABRepeat(_:)), keyEquivalent: "r")

        menu.addItem(.separator())
        let chapterItem = NSMenuItem(title: L("Chapter"), action: nil, keyEquivalent: "")
        let chapterSubmenu = NSMenu(title: L("Chapter"))
        chapterSubmenu.delegate = ChapterMenuDelegate.shared
        chapterItem.submenu = chapterSubmenu
        menu.addItem(chapterItem)

        menu.addItem(.separator())
        let sleepItem = NSMenuItem(title: L("Sleep Timer"), action: nil, keyEquivalent: "")
        let sleepSubmenu = NSMenu(title: L("Sleep Timer"))
        sleepSubmenu.delegate = SleepTimerMenuDelegate.shared
        sleepItem.submenu = sleepSubmenu
        menu.addItem(sleepItem)

        menuItem.submenu = menu
        return menuItem
    }

    private static func createAudioMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: L("Audio"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: L("Audio"))

        // Tracks section (dynamically populated)
        let tracksItem = NSMenuItem(title: L("Audio Track"), action: nil, keyEquivalent: "")
        let tracksSubmenu = NSMenu(title: L("Audio Track"))
        tracksSubmenu.delegate = TrackMenuDelegate.audio
        tracksItem.submenu = tracksSubmenu
        menu.addItem(tracksItem)
        menu.addItem(.separator())

        // Equalizer submenu — 23 presets matching Movist Pro's set, all 10-band
        // custom EQ values (see AudioEqualizerPreset.all in VLCPlayerEngine.swift).
        // Index 0 = Off (disables EQ), 1..N = preset array index + 1.
        let eqItem = NSMenuItem(title: L("Equalizer"), action: nil, keyEquivalent: "")
        let eqMenu = NSMenu(title: L("Equalizer"))
        let currentEQ = UserDefaults.standard.integer(forKey: Defaults.defaultEQPreset)

        let offItem = eqMenu.addItem(withTitle: L("Off"),
            action: #selector(AppDelegate.setEQPreset(_:)), keyEquivalent: "")
        offItem.tag = 0
        if currentEQ == 0 { offItem.state = .on }
        eqMenu.addItem(.separator())

        for (i, preset) in AudioEqualizerPreset.all.enumerated() {
            let idx = i + 1
            // EQ preset names are proper names ("Bass Booster", "R&B", etc.)
            // and have established translations; let them flow through L().
            let item = eqMenu.addItem(withTitle: L(preset.name),
                action: #selector(AppDelegate.setEQPreset(_:)), keyEquivalent: "")
            item.tag = idx
            if idx == currentEQ { item.state = .on }
        }
        eqItem.submenu = eqMenu
        menu.addItem(eqItem)

        // Output Device submenu
        let deviceItem = NSMenuItem(title: L("Output Device"), action: nil, keyEquivalent: "")
        let deviceMenu = NSMenu(title: L("Output Device"))
        deviceMenu.delegate = AudioDeviceMenuDelegate.shared
        deviceItem.submenu = deviceMenu
        menu.addItem(deviceItem)
        menu.addItem(.separator())

        // Sync section
        let syncHeader = NSMenuItem(title: L("Sync."), action: nil, keyEquivalent: "")
        syncHeader.isEnabled = false
        menu.addItem(syncHeader)
        menu.addItem(withTitle: L("Pull"), action: #selector(AppDelegate.audioSyncPull(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Push"), action: #selector(AppDelegate.audioSyncPush(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Revert Sync."), action: #selector(AppDelegate.audioSyncRevert(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        // Volume section
        let volUp = menu.addItem(withTitle: L("Increase Volume"), action: #selector(AppDelegate.volumeUp(_:)), keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
        volUp.keyEquivalentModifierMask = []
        let volDown = menu.addItem(withTitle: L("Decrease Volume"), action: #selector(AppDelegate.volumeDown(_:)), keyEquivalent: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)))
        volDown.keyEquivalentModifierMask = []
        menu.addItem(withTitle: L("Mute"), action: #selector(AppDelegate.toggleMute(_:)), keyEquivalent: "m")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createVideoMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: L("Video"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: L("Video"))

        // Tracks section (dynamically populated)
        let tracksItem = NSMenuItem(title: L("Video Track"), action: nil, keyEquivalent: "")
        let tracksSubmenu = NSMenu(title: L("Video Track"))
        tracksSubmenu.delegate = TrackMenuDelegate.video
        tracksItem.submenu = tracksSubmenu
        menu.addItem(tracksItem)
        menu.addItem(.separator())

        // Full Screen & PiP
        menu.addItem(withTitle: L("Enter Full Screen"), action: #selector(AppDelegate.toggleFullScreenAction(_:)), keyEquivalent: "\r")
        menu.addItem(withTitle: L("Picture in Picture"), action: #selector(AppDelegate.togglePiP(_:)), keyEquivalent: "p")
        menu.addItem(.separator())

        // Size
        menu.addItem(withTitle: L("Half Size"), action: #selector(AppDelegate.setHalfSize(_:)), keyEquivalent: "`")
        menu.addItem(withTitle: L("Actual Size"), action: #selector(AppDelegate.setOriginalSize(_:)), keyEquivalent: "1")
        menu.addItem(withTitle: L("Double Size"), action: #selector(AppDelegate.setDoubleSize(_:)), keyEquivalent: "2")
        menu.addItem(withTitle: L("Fit to Screen"), action: #selector(AppDelegate.fitToScreen(_:)), keyEquivalent: "4")
        menu.addItem(.separator())

        // Fill Screen & Aspect Ratio
        menu.addItem(withTitle: L("Fill Screen"), action: #selector(AppDelegate.fillScreen(_:)), keyEquivalent: "f")

        let aspectItem = NSMenuItem(title: L("Aspect Ratio"), action: nil, keyEquivalent: "")
        let aspectMenu = NSMenu(title: L("Aspect Ratio"))
        // Aspect ratios — "Default" is the only translatable label; the numeric ratios
        // are universally written the same way and use as setAspectRatio match keys.
        for (i, ratio) in ["Default", "4:3", "16:9", "16:10", "2.35:1", "2.39:1"].enumerated() {
            let title = ratio == "Default" ? L("Default") : ratio
            let item = aspectMenu.addItem(withTitle: title, action: #selector(AppDelegate.setAspectRatio(_:)), keyEquivalent: "")
            if i == 0 { item.state = .on }
        }
        aspectItem.submenu = aspectMenu
        menu.addItem(aspectItem)
        menu.addItem(.separator())

        // Rotate & Flip
        let rotL = menu.addItem(withTitle: L("Rotate Left"), action: #selector(AppDelegate.rotateLeft(_:)), keyEquivalent: "l")
        rotL.keyEquivalentModifierMask = [.shift, .command]
        let rotR = menu.addItem(withTitle: L("Rotate Right"), action: #selector(AppDelegate.rotateRight(_:)), keyEquivalent: "r")
        rotR.keyEquivalentModifierMask = [.shift, .command]
        let flipH = menu.addItem(withTitle: L("Flip Horizontal"), action: #selector(AppDelegate.flipHorizontal(_:)), keyEquivalent: "h")
        flipH.keyEquivalentModifierMask = [.shift, .command]
        let flipV = menu.addItem(withTitle: L("Flip Vertical"), action: #selector(AppDelegate.flipVertical(_:)), keyEquivalent: "v")
        flipV.keyEquivalentModifierMask = [.shift, .command]
        menu.addItem(withTitle: L("Revert Transform"), action: #selector(AppDelegate.revertTransform(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        // Crop submenu
        let cropItem = NSMenuItem(title: L("Crop"), action: nil, keyEquivalent: "")
        let cropMenu = NSMenu(title: L("Crop"))
        for crop in ["Default", "16:9", "4:3", "16:10", "1.85:1", "2.35:1"] {
            let title = crop == "Default" ? L("Default") : crop
            cropMenu.addItem(withTitle: title, action: #selector(AppDelegate.setCrop(_:)), keyEquivalent: "")
        }
        cropMenu.addItem(.separator())
        cropMenu.addItem(withTitle: L("Custom Crop…"),
                         action: #selector(AppDelegate.beginInteractiveCrop(_:)),
                         keyEquivalent: "")
        cropItem.submenu = cropMenu
        menu.addItem(cropItem)
        menu.addItem(.separator())

        // Filters submenu
        let filtersItem = NSMenuItem(title: L("Filters"), action: nil, keyEquivalent: "")
        let filtersMenu = NSMenu(title: L("Filters"))
        filtersMenu.addItem(withTitle: L("Video Equalizer…"), action: #selector(AppDelegate.showVideoEQ(_:)), keyEquivalent: "e")
        filtersMenu.addItem(withTitle: L("Video Filters…"), action: #selector(AppDelegate.showVideoFilters(_:)), keyEquivalent: "")

        // Deinterlace submenu inside Filters
        let deinterlaceItem = NSMenuItem(title: L("Deinterlace"), action: nil, keyEquivalent: "")
        let deinterlaceMenu = NSMenu(title: L("Deinterlace"))
        // Deinterlace mode names are libvlc enum strings — pass through L() so
        // localizable but keep raw English in the action handler lookup.
        for mode in ["Off", "Blend", "Bob", "Linear", "Yadif"] {
            let item = deinterlaceMenu.addItem(withTitle: L(mode), action: #selector(AppDelegate.setDeinterlace(_:)), keyEquivalent: "")
            if mode == "Off" { item.state = .on }
        }
        deinterlaceItem.submenu = deinterlaceMenu
        filtersMenu.addItem(deinterlaceItem)

        filtersItem.submenu = filtersMenu
        menu.addItem(filtersItem)
        menu.addItem(.separator())

        // Screenshot
        let ss = menu.addItem(withTitle: L("Save Screenshot"), action: #selector(AppDelegate.saveScreenshot(_:)), keyEquivalent: "s")
        ss.keyEquivalentModifierMask = [.option, .command]

        menuItem.submenu = menu
        return menuItem
    }

    private static func createSubtitleMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: L("Subtitle"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: L("Subtitle"))
        // Delegate keeps the background-opacity slider synced to UserDefaults on open
        menu.delegate = SubtitleMenuDelegate.shared

        // Tracks section (dynamically populated)
        let tracksItem = NSMenuItem(title: L("Subtitle Track"), action: nil, keyEquivalent: "")
        let tracksSubmenu = NSMenu(title: L("Subtitle Track"))
        tracksSubmenu.delegate = TrackMenuDelegate.subtitle
        tracksItem.submenu = tracksSubmenu
        menu.addItem(tracksItem)
        menu.addItem(.separator())

        // Display Type submenu
        let displayItem = NSMenuItem(title: L("Display Type"), action: nil, keyEquivalent: "")
        let displayMenu = NSMenu(title: L("Display Type"))
        for (i, pos) in ["Bottom of Video", "Bottom of Screen", "Letterbox"].enumerated() {
            let item = displayMenu.addItem(withTitle: L(pos), action: #selector(AppDelegate.setSubtitlePosition(_:)), keyEquivalent: "")
            if i == 0 { item.state = .on }
        }
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)

        // Text Color submenu — full HTML/CSS 16-color palette (matches VLC).
        // Writes to UserDefaults; SubtitleOverlayView KVO picks it up live.
        let textColorItem = NSMenuItem(title: L("Text Color"), action: nil, keyEquivalent: "")
        let textColorMenu = NSMenu(title: L("Text Color"))
        let currentTextColor = UserDefaults.standard.integer(forKey: Defaults.subtitleColor)
        for (i, entry) in SubtitleOverlayView.namedColors.enumerated() {
            let item = textColorMenu.addItem(withTitle: L(entry.name),
                action: #selector(AppDelegate.setSubtitleTextColor(_:)), keyEquivalent: "")
            item.tag = i
            item.image = SubtitleOverlayView.swatchImage(for: entry.color)
            if i == currentTextColor { item.state = .on }
        }
        textColorItem.submenu = textColorMenu
        menu.addItem(textColorItem)

        // Outline Thickness submenu
        let outlineItem = NSMenuItem(title: L("Outline Thickness"), action: nil, keyEquivalent: "")
        let outlineMenu = NSMenu(title: L("Outline Thickness"))
        let currentOutline = UserDefaults.standard.integer(forKey: Defaults.subtitleOutlineThickness)
        for thickness in 0...6 {
            let title = thickness == 0 ? L("None") : String(format: L("%d px"), thickness)
            let item = outlineMenu.addItem(withTitle: title, action: #selector(AppDelegate.setSubtitleOutlineThickness(_:)), keyEquivalent: "")
            item.tag = thickness
            if thickness == currentOutline { item.state = .on }
        }
        outlineItem.submenu = outlineMenu
        menu.addItem(outlineItem)

        menu.addItem(.separator())

        // Inline Background Opacity slider (VLC-style)
        let opacityItem = NSMenuItem()
        opacityItem.view = SubtitleOpacitySliderView.shared
        menu.addItem(opacityItem)

        // Background Color submenu — same HTML/CSS 16-color palette as Text Color
        let bgColorItem = NSMenuItem(title: L("Background Color"), action: nil, keyEquivalent: "")
        let bgColorMenu = NSMenu(title: L("Background Color"))
        let currentBgColor = UserDefaults.standard.integer(forKey: Defaults.subtitleBackgroundColor)
        for (i, entry) in SubtitleOverlayView.namedColors.enumerated() {
            let item = bgColorMenu.addItem(withTitle: L(entry.name),
                action: #selector(AppDelegate.setSubtitleBackgroundColor(_:)), keyEquivalent: "")
            item.tag = i
            item.image = SubtitleOverlayView.swatchImage(for: entry.color)
            if i == currentBgColor { item.state = .on }
        }
        bgColorItem.submenu = bgColorMenu
        menu.addItem(bgColorItem)

        menu.addItem(.separator())

        // Hide Subtitles
        let hide = menu.addItem(withTitle: L("Hide Subtitles"), action: #selector(AppDelegate.toggleSubtitles(_:)), keyEquivalent: "v")
        hide.keyEquivalentModifierMask = [.control]
        menu.addItem(.separator())

        // Add Subtitle File
        menu.addItem(withTitle: L("Add Subtitle File…"), action: #selector(AppDelegate.addSubtitleFile(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Search OpenSubtitles…"),
                     action: #selector(AppDelegate.searchOpenSubtitlesAction(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())

        // Sync section
        let syncHeader = NSMenuItem(title: L("Sync."), action: nil, keyEquivalent: "")
        syncHeader.isEnabled = false
        menu.addItem(syncHeader)
        menu.addItem(withTitle: L("Pull"), action: #selector(AppDelegate.subtitleSyncPull(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Push"), action: #selector(AppDelegate.subtitleSyncPush(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Revert Sync."), action: #selector(AppDelegate.subtitleSyncRevert(_:)), keyEquivalent: "")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createPlaylistMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: L("Playlist"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: L("Playlist"))

        let showPlaylist = menu.addItem(withTitle: L("Show Playlist"), action: #selector(AppDelegate.togglePlaylistPanel(_:)), keyEquivalent: "p")
        showPlaylist.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Repeat Off"), action: #selector(AppDelegate.setRepeatOff(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Repeat One"), action: #selector(AppDelegate.setRepeatOne(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Repeat All"), action: #selector(AppDelegate.setRepeatAll(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Shuffle"), action: #selector(AppDelegate.toggleShuffle(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Previous"), action: #selector(AppDelegate.previousTrack(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Next"), action: #selector(AppDelegate.nextTrack(_:)), keyEquivalent: "")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createCastMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: L("Cast"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: L("Cast"))

        // AirPlay, Chromecast, DLNA: proper brand names, kept as-is across languages
        let airplayItem = NSMenuItem(title: "AirPlay", action: nil, keyEquivalent: "")
        let airplaySubmenu = NSMenu(title: "AirPlay")
        airplaySubmenu.delegate = AirPlayMenuDelegate.shared
        airplayItem.submenu = airplaySubmenu
        menu.addItem(airplayItem)

        menu.addItem(withTitle: L("Play on External Display"), action: #selector(AppDelegate.playOnExternalDisplay(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        let chromecastItem = NSMenuItem(title: "Chromecast", action: nil, keyEquivalent: "")
        let chromecastSubmenu = NSMenu(title: "Chromecast")
        chromecastSubmenu.delegate = ChromecastMenuDelegate.shared
        chromecastItem.submenu = chromecastSubmenu
        menu.addItem(chromecastItem)

        menu.addItem(withTitle: "DLNA", action: #selector(AppDelegate.showDLNA(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Disconnect"), action: #selector(AppDelegate.disconnectCast(_:)), keyEquivalent: "")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createWindowMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: L("Window"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: L("Window"))

        menu.addItem(withTitle: L("Minimize"), action: #selector(AppDelegate.minimizeAction(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: L("Zoom"), action: #selector(AppDelegate.zoomAction(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Keep on Top"), action: #selector(AppDelegate.toggleAlwaysOnTop(_:)), keyEquivalent: "t")
        let miniItem = menu.addItem(withTitle: L("Music Mode"),
            action: #selector(AppDelegate.toggleMiniPlayer(_:)), keyEquivalent: "m")
        miniItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Media Inspector"), action: #selector(AppDelegate.showInspector(_:)), keyEquivalent: "i")

        NSApplication.shared.windowsMenu = menu
        menuItem.submenu = menu
        return menuItem
    }

    private static func createHelpMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: L("Help"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: L("Help"))
        menu.addItem(withTitle: L("Awesome Player Help"), action: #selector(NSApplication.showHelp(_:)), keyEquivalent: "?")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Reveal Crash Logs in Finder"),
                     action: #selector(AppDelegate.revealCrashLogsAction(_:)),
                     keyEquivalent: "")
        menu.addItem(withTitle: L("Report an Issue on GitHub"),
                     action: #selector(AppDelegate.reportIssueAction(_:)),
                     keyEquivalent: "")
        NSApplication.shared.helpMenu = menu
        menuItem.submenu = menu
        return menuItem
    }
}
