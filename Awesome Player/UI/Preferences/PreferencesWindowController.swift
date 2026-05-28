import Cocoa

class PreferencesWindowController: NSWindowController {
    private let tabView = NSTabView()

    /// Stable identifier (English, never changes) + dynamic localized label +
    /// SF Symbol name + tint color. The freshly-built view is rebuilt on each
    /// rebuildTabs() call so its labels are baked with the current locale's
    /// L() values. The English `id` is used as the NSTabViewItem identifier
    /// and the NSToolbarItem identifier so toolbar selection state stays
    /// stable across language switches.
    private struct TabDef {
        let id: String
        let label: String
        let icon: String
        let color: NSColor
        let view: NSView
    }

    private var tabs: [TabDef] = []

    private static func makeTabs() -> [TabDef] {
        [
            TabDef(id: "General",  label: L("General"),  icon: "gearshape.fill",                       color: .systemGray,   view: GeneralPrefsView()),
            TabDef(id: "Open",     label: L("Open"),     icon: "doc.badge.plus",                       color: .systemBlue,   view: MediaOpenPrefsView()),
            TabDef(id: "Playback", label: L("Playback"), icon: "play.circle.fill",                     color: .systemGreen,  view: PlaybackPrefsView()),
            TabDef(id: "Video",    label: L("Video"),    icon: "film.fill",                            color: .systemPurple, view: VideoPrefsView()),
            TabDef(id: "Audio",    label: L("Audio"),    icon: "speaker.wave.3.fill",                  color: .systemPink,   view: AudioPrefsView()),
            TabDef(id: "Subtitle", label: L("Subtitle"), icon: "captions.bubble.fill",                 color: .systemTeal,   view: SubtitlePrefsView()),
            TabDef(id: "Screen",   label: L("Screen"),   icon: "arrow.up.left.and.arrow.down.right",   color: .systemIndigo, view: FullScreenPrefsView()),
            TabDef(id: "Input",    label: L("Input"),    icon: "keyboard.fill",                        color: .systemBrown,  view: InputPrefsView()),
            TabDef(id: "Cast",     label: L("Cast"),     icon: "tv.fill",                              color: .systemRed,    view: CastPrefsView()),
        ]
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .visible
        window.center()
        super.init(window: window)

        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .noTabsNoBorder
        window.contentView?.addSubview(tabView)
        if let contentView = window.contentView {
            NSLayoutConstraint.activate([
                tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
                tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
                tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            ])
        }

        rebuildTabs(selectedId: "General")

        DispatchQueue.main.async { [weak self] in
            self?.resizeWindowToFitTab(animated: false)
        }

        // Live-refresh in place on language change instead of forcing the
        // window to close. AppDelegate's cached preferencesController stays
        // valid; only the views and toolbar items get re-instantiated.
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChange),
                                                name: .languageDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func handleLanguageChange() {
        let selectedId = tabView.selectedTabViewItem?.identifier as? String ?? "General"
        rebuildTabs(selectedId: selectedId)
    }

    /// Builds tab content + toolbar from a fresh `makeTabs()`. Safe to call
    /// multiple times — previous tab items are removed first. The toolbar is
    /// rebuilt with a new NSToolbar instance because NSToolbar caches item
    /// titles internally and there's no public API to refresh them in place.
    private func rebuildTabs(selectedId: String) {
        tabs = Self.makeTabs()

        // Wipe and re-add tab items
        for item in tabView.tabViewItems.reversed() {
            tabView.removeTabViewItem(item)
        }
        var selectedIndex = 0
        for (i, tab) in tabs.enumerated() {
            let item = NSTabViewItem(identifier: tab.id)
            item.label = tab.label
            item.view = tab.view
            tabView.addTabViewItem(item)
            if tab.id == selectedId { selectedIndex = i }
        }
        tabView.selectTabViewItem(at: selectedIndex)

        // Rebuild toolbar so localized labels appear on the toolbar items
        let toolbar = NSToolbar(identifier: "PrefsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = Set(tabs.map { NSToolbarItem.Identifier($0.id) })
        window?.toolbar = toolbar
        window?.toolbarStyle = .preference
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(tabs[selectedIndex].id)

        window?.title = tabs[selectedIndex].label
    }

    @objc private func tabClicked(_ sender: NSToolbarItem) {
        guard let tab = tabs.first(where: { $0.id == sender.itemIdentifier.rawValue }),
              let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabView.selectTabViewItem(at: index)
        window?.title = tab.label
        resizeWindowToFitTab(animated: true)
    }

    private func resizeWindowToFitTab(animated: Bool) {
        guard let window = window,
              let tabContent = tabView.selectedTabViewItem?.view else { return }

        tabContent.layoutSubtreeIfNeeded()

        // Find the actual content height by looking through scroll view → document view → stack
        var contentHeight: CGFloat = 0
        for sub in tabContent.subviews {
            if let scrollView = sub as? NSScrollView,
               let docView = scrollView.documentView {
                docView.layoutSubtreeIfNeeded()
                let fitting = docView.fittingSize
                contentHeight = max(contentHeight, fitting.height)
            } else {
                let fitting = sub.fittingSize
                contentHeight = max(contentHeight, fitting.height)
            }
        }
        contentHeight += 24

        let maxHeight = (window.screen?.visibleFrame.height ?? 800) * 0.7
        contentHeight = min(contentHeight, maxHeight)
        contentHeight = max(contentHeight, 300)

        let toolbarHeight = window.frame.height - window.contentLayoutRect.height
        let newWindowHeight = contentHeight + toolbarHeight
        let frame = NSRect(
            x: window.frame.origin.x,
            y: window.frame.origin.y + window.frame.height - newWindowHeight,
            width: window.frame.width,
            height: newWindowHeight
        )

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }
}

extension PreferencesWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        tabs.map { NSToolbarItem.Identifier($0.id) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        tabs.map { NSToolbarItem.Identifier($0.id) }
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        tabs.map { NSToolbarItem.Identifier($0.id) }
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = tabs.first(where: { $0.id == itemIdentifier.rawValue }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.label
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tab.color]))
        item.image = NSImage(systemSymbolName: tab.icon, accessibilityDescription: tab.label)?
            .withSymbolConfiguration(config)
        item.image?.isTemplate = false
        item.target = self
        item.action = #selector(tabClicked(_:))
        return item
    }
}

// MARK: - Individual Preference Views

class GeneralPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addSectionHeader(stack, L("Appearance"))
        addPopupRow(stack, L("Theme:"), key: Defaults.theme, items: [L("System"), L("Dark"), L("Light")])
        addToggleRow(stack, L("Transparent title bar"), key: Defaults.transparentTitleBar)

        addSectionHeader(stack, L("Language"))
        addLanguageRow(stack)

        addSectionHeader(stack, L("Behavior"))
        addToggleRow(stack, L("Resume playback position on reopen"), key: Defaults.resumePlayback)
        addToggleRow(stack, L("Quit when last window closed"), key: Defaults.quitOnLastWindowClosed)
        addToggleRow(stack, L("Restore window position on launch"), key: Defaults.restoreWindowPosition)

        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Per-app language override. Writes to the standard macOS AppleLanguages
    /// key so the change is identical to what System Settings → Language &
    /// Region → Applications would do; macOS then loads strings from the
    /// matching .lproj at next launch.
    private func addLanguageRow(_ stack: NSStackView) {
        let popup = NSPopUpButton()
        // First entry = follow system locale (clears the override)
        popup.addItem(withTitle: L("System Default"))
        for entry in LanguagePicker.languages {
            popup.addItem(withTitle: entry.displayName)
        }
        // Reflect current override
        let current = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first ?? ""
        if let idx = LanguagePicker.languages.firstIndex(where: { current.hasPrefix($0.code) }) {
            popup.selectItem(at: idx + 1)
        } else {
            popup.selectItem(at: 0)
        }
        popup.target = LanguagePicker.shared
        popup.action = #selector(LanguagePicker.languageChanged(_:))
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        addRow(stack, L("Display language:"), popup)
    }
}

/// Handles the language popup's action: write AppleLanguages, prompt the user
/// to relaunch, and offer to do it for them.
final class LanguagePicker: NSObject {
    static let shared = LanguagePicker()

    struct Entry {
        /// AppleLanguages code (matches our .lproj names)
        let code: String
        /// Endonym shown in the picker so users find their language regardless
        /// of the current UI language (e.g. a Russian speaker sees "Русский"
        /// even if the app is currently in English).
        let displayName: String
    }

    static let languages: [Entry] = [
        Entry(code: "en",      displayName: "English"),
        Entry(code: "zh-Hans", displayName: "简体中文"),
        Entry(code: "zh-Hant", displayName: "繁體中文"),
        Entry(code: "yue",     displayName: "廣東話"),
        Entry(code: "ja",      displayName: "日本語"),
        Entry(code: "ko",      displayName: "한국어"),
        Entry(code: "es",      displayName: "Español"),
        Entry(code: "fr",      displayName: "Français"),
        Entry(code: "de",      displayName: "Deutsch"),
        Entry(code: "pt-BR",   displayName: "Português (Brasil)"),
        Entry(code: "ru",      displayName: "Русский"),
    ]

    @objc func languageChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        let code: String? = idx == 0 ? nil : Self.languages[idx - 1].code

        // Swap the active bundle in LanguageManager → L() returns new-locale
        // strings starting with the next call. Also writes AppleLanguages so
        // the choice persists across launches.
        LanguageManager.shared.setLanguage(code)

        // The main menu is set once at app launch; rebuild it so the menu
        // bar reflects the new language immediately.
        NSApplication.shared.mainMenu = nil
        MenuManager.setupMainMenu()

        // The Preferences window itself observes .languageDidChange and
        // rebuilds its tabs / toolbar in place (PreferencesWindowController
        // .handleLanguageChange), so we don't need to close it. The rest of
        // the app's UI is either dynamic or icon-based — picks up the new
        // language on the next render with no extra work.
    }
}

class MediaOpenPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addSectionHeader(stack, "Playback Engine")
        addPopupRow(stack, "Default engine:", key: Defaults.defaultEngine, items: ["Auto", "AVPlayer", "FFmpeg"])

        addSectionHeader(stack, "File Opening")
        addToggleRow(stack, "Auto-find series files in same folder", key: Defaults.autoFindSeriesFiles)
        addToggleRow(stack, "Auto-load next file in folder", key: Defaults.autoLoadNextFile)
        addToggleRow(stack, "Open in new window", key: Defaults.openInNewWindow)

        addSectionHeader(stack, "Subtitles")
        addToggleRow(stack, "Auto-load matching subtitle files", key: Defaults.autoLoadSubtitles)
        addPopupRow(stack, "Subtitle search:", key: Defaults.subtitleSearchScope, items: ["Same directory only", "Include subdirectories"])
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class PlaybackPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addSectionHeader(stack, "Speed")
        addSliderRow(stack, "Default speed:", min: 0.25, max: 4.0, value: 1.0, key: Defaults.defaultSpeed)

        addSectionHeader(stack, "Seeking")
        addSliderRow(stack, "Short seek interval (s):", min: 1, max: 30, value: 5, key: Defaults.shortSeekInterval)
        addSliderRow(stack, "Long seek interval (s):", min: 5, max: 120, value: 30, key: Defaults.longSeekInterval)
        addToggleRow(stack, "Key-frame seeking (faster)", key: Defaults.keyFrameSeeking)

        addSectionHeader(stack, "Behavior")
        addToggleRow(stack, "Auto-play on open", key: Defaults.autoPlayOnOpen)
        addPopupRow(stack, "When media ends:", key: Defaults.mediaEndAction, items: ["Do Nothing", "Close Media", "Play Next", "Loop"])

        addSectionHeader(stack, "A-B Loop")
        addSliderRow(stack, "Gap between loops (s):", min: 0, max: 5, value: 0, key: Defaults.abLoopGap)

        addSectionHeader(stack, "Playlist")
        addPopupRow(stack, "Repeat mode:", key: Defaults.repeatMode, items: ["Off", "One", "All"])
        addToggleRow(stack, "Shuffle", key: Defaults.shuffle)
        addPopupRow(stack, "When playlist ends:", key: Defaults.playlistEndAction, items: ["Do Nothing", "Close Window", "Quit"])
        addToggleRow(stack, "Auto-add files from directory", key: Defaults.autoAddFromDirectory)
        addPopupRow(stack, "Sort order:", key: Defaults.sortOrder, items: ["Name (ascending)", "Name (descending)", "Date modified", "File size"])
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class VideoPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addSectionHeader(stack, "Display")
        addPopupRow(stack, "Default aspect ratio:", key: Defaults.defaultAspectRatio, items: ["Auto", "4:3", "16:9", "16:10", "2.35:1", "2.39:1"])
        addPopupRow(stack, "Default window size:", key: Defaults.defaultVideoSize, items: ["Fit to Screen", "Original Size", "Half Size", "Double Size", "50%", "75%", "150%", "200%"])
        addPopupRow(stack, "Fill screen mode:", key: Defaults.fillScreenMode, items: ["Stretch to Fill", "Crop to Fill"])

        addSectionHeader(stack, "HDR")
        addPopupRow(stack, "HDR tone mapping:", key: Defaults.hdrToneMappingMode, items: ["System Default", "Always HDR", "Force SDR"])

        addSectionHeader(stack, "Video Equalizer Defaults")
        addSliderRow(stack, "Brightness:", min: -0.5, max: 0.5, value: 0, key: Defaults.defaultBrightness)
        addSliderRow(stack, "Contrast:", min: 0.5, max: 2.0, value: 1.0, key: Defaults.defaultContrast)
        addSliderRow(stack, "Saturation:", min: 0, max: 2.0, value: 1.0, key: Defaults.defaultSaturation)

        addSectionHeader(stack, "Screenshot")
        addPopupRow(stack, "Format:", key: Defaults.screenshotFormat, items: ["PNG", "JPEG", "TIFF"])
        addPopupRow(stack, "Save to:", key: Defaults.screenshotSavePath, items: ["Desktop", "Pictures", "Downloads", "Custom…"])
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class AudioPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addSectionHeader(stack, "Volume")
        addSliderRow(stack, "Default volume:", min: 0, max: 1, value: 1, key: Defaults.defaultVolume)
        addToggleRow(stack, "Allow extended volume (up to 400%)", key: Defaults.extendedVolume)

        addSectionHeader(stack, "Passthrough")
        addPopupRow(stack, "Audio passthrough:", key: Defaults.passthroughMode, items: ["Auto-detect", "Always On", "Off"])

        addSectionHeader(stack, "Equalizer")
        addPopupRow(stack, "Default EQ preset:", key: Defaults.defaultEQPreset, items: ["Flat", "Bass Boost", "Treble Boost", "Vocal", "Rock", "Jazz", "Classical", "Electronic"])

        addSectionHeader(stack, "Audio Processing")
        addToggleRow(stack, "Enable compressor (night mode)", key: Defaults.compressorEnabled)
        addToggleRow(stack, "Enable spatializer (headphone surround)", key: Defaults.spatializerEnabled)
        addSliderRow(stack, "Stereo width:", min: 0, max: 200, value: 100, key: Defaults.stereoWidth)

        addSectionHeader(stack, "Normalization")
        addToggleRow(stack, "Enable loudness normalization", key: Defaults.normalizationEnabled)
        addSliderRow(stack, "Target loudness (LUFS):", min: -24, max: -6, value: -14, key: Defaults.normalizationTarget)

        addSectionHeader(stack, "Sync")
        addSliderRow(stack, "Audio delay step (ms):", min: 10, max: 500, value: 100, key: Defaults.audioDelayStep)
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class SubtitlePrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addSectionHeader(stack, "Loading")
        addToggleRow(stack, "Auto-load embedded subtitles", key: Defaults.autoLoadEmbedded)
        addToggleRow(stack, "Auto-load external subtitle files", key: Defaults.autoLoadExternal)
        addPopupRow(stack, "Preferred language:", key: Defaults.subtitleLanguage, items: ["Any", "English", "Chinese (Simplified)", "Chinese (Traditional)", "Japanese", "Korean", "Spanish", "French", "German"])

        addSectionHeader(stack, "Encoding")
        addPopupRow(stack, "Default encoding:", key: Defaults.defaultEncoding, items: ["UTF-8", "Auto-detect", "GBK (Chinese)", "Shift-JIS (Japanese)", "EUC-KR (Korean)", "ISO-8859-1 (Latin)", "Windows-1252 (Western)"])

        addSectionHeader(stack, "Appearance")
        addPopupRow(stack, "Font:", key: Defaults.subtitleFont, items: ["System Default", "Helvetica Neue", "Arial", "SF Pro", "PingFang SC"])
        addSliderRow(stack, "Font size:", min: 12, max: 60, value: 24, key: Defaults.subtitleFontSize)
        addPopupRow(stack, "Text color:", key: Defaults.subtitleColor, items: ["White", "Yellow", "Green", "Cyan"])
        addPopupRow(stack, "Outline:", key: Defaults.subtitleOutline, items: ["Black outline", "Shadow only", "Background box", "None"])

        addSectionHeader(stack, "Position")
        addPopupRow(stack, "Display position:", key: Defaults.subtitlePosition, items: ["Bottom of Video", "Bottom of Screen", "Upper Letterbox", "Lower Letterbox"])

        addSectionHeader(stack, "Sync")
        addSliderRow(stack, "Delay step (s):", min: 0.05, max: 1.0, value: 0.1, key: Defaults.subtitleDelayStep)
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class FullScreenPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addSectionHeader(stack, "Enter / Exit")
        addToggleRow(stack, "Auto-enter fullscreen on open", key: Defaults.autoEnterFullscreen)
        addToggleRow(stack, "Pause when exiting fullscreen", key: Defaults.pauseOnExitFullscreen)
        addToggleRow(stack, "Start playing when entering fullscreen", key: Defaults.playOnEnterFullscreen)

        addSectionHeader(stack, "Display")
        addToggleRow(stack, "Black out other screens", key: Defaults.blackOutOtherScreens)
        addPopupRow(stack, "Control bar:", key: Defaults.fullscreenControlBar, items: ["Auto-hide (3 seconds)", "Auto-hide (5 seconds)", "Always Show"])

        addSectionHeader(stack, "Time Display")
        addPopupRow(stack, "Time OSD position:", key: Defaults.timeOSDPosition, items: ["Top-left", "Top-center", "Top-right", "Hidden"])
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class InputPrefsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let shortcuts: [(action: String, key: String)] = [
        ("Play / Pause", "Space"),
        ("Seek ±5 seconds", "← / →"),
        ("Seek ±30 seconds", "⇧← / ⇧→"),
        ("Seek ±60 seconds", "⌘← / ⌘→"),
        ("Volume up / down", "↑ / ↓"),
        ("Mute / Unmute", "M"),
        ("Toggle fullscreen", "F"),
        ("Speed -/+ 0.25x", "[ / ]"),
        ("Reset speed 1.0x", "\\"),
        ("Frame step fwd / bwd", ". / ,"),
        ("Next / prev chapter", "⌘N / ⌘P"),
        ("A-B loop", "R"),
        ("Open file", "⌘O"),
        ("Keep on top", "⌘T"),
        ("Save screenshot", "⌥⌘S"),
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)

        let stack = makePrefsStack()

        addSectionHeader(stack, "Media Keys")
        addToggleRow(stack, "Enable media keys (Play/Pause, Next, Prev)", key: Defaults.mediaKeyEnabled)

        addSectionHeader(stack, "Escape Key")
        addPopupRow(stack, "Escape key action:", key: Defaults.escapeKeyBehavior, items: ["Exit Fullscreen", "Close Panel", "Stop Playback"])

        addSectionHeader(stack, "Keyboard Shortcuts")

        let actionCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionCol.title = "Action"
        actionCol.width = 200
        let keyCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("key"))
        keyCol.title = "Shortcut"
        keyCol.width = 120
        tableView.addTableColumn(actionCol)
        tableView.addTableColumn(keyCol)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 22
        tableView.usesAlternatingRowBackgroundColors = true

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 220).isActive = true
        stack.addArrangedSubview(scrollView)

        addSectionHeader(stack, "Mouse")
        addPopupRow(stack, "Single click:", key: Defaults.singleClickAction, items: ["Play / Pause", "Nothing"])
        addPopupRow(stack, "Double click:", key: Defaults.doubleClickAction, items: ["Toggle Fullscreen", "Nothing"])
        addPopupRow(stack, "Middle click:", key: Defaults.middleClickAction, items: ["Mute / Unmute", "Play / Pause", "Nothing"])
        addPopupRow(stack, "Right click:", key: Defaults.rightClickAction, items: ["Context Menu", "Nothing"])

        addSectionHeader(stack, "Scroll Wheel")
        addPopupRow(stack, "Scroll action:", key: Defaults.scrollWheelAction, items: ["Volume", "Seek", "Nothing"])
        addSliderRow(stack, "Scroll sensitivity:", min: 1, max: 10, value: 5, key: Defaults.scrollWheelSensitivity)

        addSectionHeader(stack, "Trackpad")
        addPopupRow(stack, "Pinch gesture:", key: Defaults.pinchGestureAction, items: ["Zoom Video", "Resize Window", "Nothing"])

        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }

    func numberOfRows(in tableView: NSTableView) -> Int { shortcuts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text: String
        if tableColumn?.identifier.rawValue == "action" {
            text = shortcuts[row].action
        } else {
            text = shortcuts[row].key
        }
        let label = NSTextField(labelWithString: text)
        label.font = tableColumn?.identifier.rawValue == "key"
            ? .monospacedSystemFont(ofSize: 12, weight: .medium)
            : .systemFont(ofSize: 12)
        return label
    }
}

class CastPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addSectionHeader(stack, "Connection")
        addPopupRow(stack, "Default behavior:", key: Defaults.castDefaultBehavior, items: ["Ask every time", "Auto-connect to last device"])
        addToggleRow(stack, "Auto-disconnect on window close", key: Defaults.autoDisconnectOnClose)
        addToggleRow(stack, "Resume local playback on disconnect", key: Defaults.resumeLocalOnDisconnect)

        addSectionHeader(stack, "AirPlay")
        addPopupRow(stack, "Show AirPlay button:", key: Defaults.airplayButtonVisibility, items: ["Always", "When device available", "Never"])

        addSectionHeader(stack, "Chromecast")
        addPopupRow(stack, "Transcoding quality:", key: Defaults.chromecastQuality, items: ["Low (720p)", "Medium (1080p)", "High (4K)"])

        addSectionHeader(stack, "DLNA")
        addPopupRow(stack, "Transcoding quality:", key: Defaults.dlnaQuality, items: ["Low (720p)", "Medium (1080p)", "High (4K)"])
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Helpers

extension NSView {
    func makePrefsStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    func embed(_ stack: NSStackView) {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 10).isActive = true
        stack.addArrangedSubview(spacer)

        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false

        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.frame = bounds
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = container
        addSubview(scrollView)

        // Pin container width to scroll view so it doesn't scroll horizontally
        container.widthAnchor.constraint(equalTo: scrollView.widthAnchor).isActive = true
    }

    func addSectionHeader(_ stack: NSStackView, _ title: String) {
        if !stack.arrangedSubviews.isEmpty {
            let spacer = NSView()
            spacer.heightAnchor.constraint(equalToConstant: 4).isActive = true
            stack.addArrangedSubview(spacer)
        }
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        stack.addArrangedSubview(label)
        let sep = NSBox()
        sep.boxType = .separator
        sep.widthAnchor.constraint(equalToConstant: 400).isActive = true
        stack.addArrangedSubview(sep)
    }

    func addRow(_ stack: NSStackView, _ label: String, _ control: NSView) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 12)
        lbl.lineBreakMode = .byTruncatingTail
        lbl.widthAnchor.constraint(equalToConstant: 300).isActive = true

        row.addArrangedSubview(lbl)
        row.addArrangedSubview(control)
        stack.addArrangedSubview(row)
    }

    /// Toggle bound to UserDefaults via Cocoa Bindings — reads/writes automatically.
    func addToggleRow(_ stack: NSStackView, _ label: String, key: String) {
        let toggle = NSSwitch()
        toggle.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values.\(key)", options: nil)
        addRow(stack, label, toggle)
    }

    /// Slider bound to UserDefaults via Cocoa Bindings — reads/writes automatically.
    func addSliderRow(_ stack: NSStackView, _ label: String, min: Double, max: Double, value: Double, key: String) {
        let slider = NSSlider()
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = value // fallback; binding will override if key exists
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 250).isActive = true
        slider.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values.\(key)", options: nil)
        addRow(stack, label, slider)
    }

    /// Popup button bound to UserDefaults via Cocoa Bindings (selectedIndex).
    func addPopupRow(_ stack: NSStackView, _ label: String, key: String, items: [String]) {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: items)
        popup.isEnabled = true
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        popup.bind(.selectedIndex, to: NSUserDefaultsController.shared, withKeyPath: "values.\(key)", options: nil)
        addRow(stack, label, popup)
    }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
