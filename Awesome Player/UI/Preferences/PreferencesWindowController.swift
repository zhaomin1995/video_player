import Cocoa

class PreferencesWindowController: NSWindowController {
    private let tabView = NSTabView()

    private let tabs: [(String, String, NSColor, NSView)] = [
        ("General", "gearshape.fill", .systemGray, GeneralPrefsView()),
        ("Open", "doc.badge.plus", .systemBlue, MediaOpenPrefsView()),
        ("Playback", "play.circle.fill", .systemGreen, PlaybackPrefsView()),
        ("Video", "film.fill", .systemPurple, VideoPrefsView()),
        ("Audio", "speaker.wave.3.fill", .systemPink, AudioPrefsView()),
        ("Subtitle", "captions.bubble.fill", .systemTeal, SubtitlePrefsView()),
        ("Screen", "arrow.up.left.and.arrow.down.right", .systemIndigo, FullScreenPrefsView()),
        ("Input", "keyboard.fill", .systemBrown, InputPrefsView()),
        ("Cast", "tv.fill", .systemRed, CastPrefsView()),
    ]

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "General"
        window.titleVisibility = .visible
        window.center()
        super.init(window: window)
        setupTabs()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupTabs() {
        let toolbar = NSToolbar(identifier: "PrefsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = Set(tabs.map { NSToolbarItem.Identifier($0.0) })
        window?.toolbar = toolbar
        window?.toolbarStyle = .preference

        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .noTabsNoBorder
        window?.contentView?.addSubview(tabView)

        for (i, (name, _, _, view)) in tabs.enumerated() {
            let item = NSTabViewItem(identifier: name)
            item.label = name
            view.translatesAutoresizingMaskIntoConstraints = false
            item.view = view
            tabView.addTabViewItem(item)

            if i == 0 {
                toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(name)
            }
        }

        if let contentView = window?.contentView {
            NSLayoutConstraint.activate([
                tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
                tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
                tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            ])
        }
    }

    @objc private func tabClicked(_ sender: NSToolbarItem) {
        for (i, (name, _, _, _)) in tabs.enumerated() {
            if name == sender.itemIdentifier.rawValue {
                tabView.selectTabViewItem(at: i)
                window?.title = name
                break
            }
        }
    }
}

extension PreferencesWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        tabs.map { NSToolbarItem.Identifier($0.0) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        tabs.map { NSToolbarItem.Identifier($0.0) }
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        tabs.map { NSToolbarItem.Identifier($0.0) }
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = tabs.first(where: { $0.0 == itemIdentifier.rawValue }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.0
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tab.2]))
        item.image = NSImage(systemSymbolName: tab.1, accessibilityDescription: tab.0)?
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
        addSectionHeader(stack, "Appearance")
        addRow(stack, "Theme:", NSPopUpButton().configured { $0.addItems(withTitles: ["System", "Dark", "Light"]) })
        addToggleRow(stack, "Transparent title bar", key: Defaults.transparentTitleBar)

        addSectionHeader(stack, "Behavior")
        addToggleRow(stack, "Resume playback position on reopen", key: Defaults.resumePlayback)
        addToggleRow(stack, "Quit when last window closed", key: Defaults.quitOnLastWindowClosed)
        addToggleRow(stack, "Restore window position on launch", key: Defaults.resumePlayback)

        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class MediaOpenPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addSectionHeader(stack, "Playback Engine")
        addRow(stack, "Default engine:", NSPopUpButton().configured { $0.addItems(withTitles: ["Auto", "AVPlayer", "FFmpeg"]) })

        addSectionHeader(stack, "File Opening")
        addToggleRow(stack, "Auto-find series files in same folder", key: Defaults.autoFindSeriesFiles)
        addToggleRow(stack, "Auto-load next file in folder", key: Defaults.autoLoadNextFile)
        addToggleRow(stack, "Open in new window", key: Defaults.openInNewWindow)

        addSectionHeader(stack, "Subtitles")
        addToggleRow(stack, "Auto-load matching subtitle files", key: Defaults.autoLoadSubtitles)
        addRow(stack, "Subtitle search:", NSPopUpButton().configured { $0.addItems(withTitles: ["Same directory only", "Include subdirectories"]) })
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
        addToggleRow(stack, "Key-frame seeking (faster, less precise)", key: Defaults.keyFrameSeeking)

        addSectionHeader(stack, "Behavior")
        addToggleRow(stack, "Auto-play on open", key: Defaults.autoPlayOnOpen)
        addRow(stack, "When media ends:", NSPopUpButton().configured { $0.addItems(withTitles: ["Do Nothing", "Close Media", "Play Next", "Loop"]) })

        addSectionHeader(stack, "A-B Loop")
        addSliderRow(stack, "Gap between loops (s):", min: 0, max: 5, value: 0, key: Defaults.abLoopGap)

        addSectionHeader(stack, "Playlist")
        addRow(stack, "Repeat mode:", NSPopUpButton().configured { $0.addItems(withTitles: ["Off", "One", "All"]) })
        addToggleRow(stack, "Shuffle", key: Defaults.shuffle)
        addRow(stack, "When playlist ends:", NSPopUpButton().configured { $0.addItems(withTitles: ["Do Nothing", "Close Window", "Quit"]) })
        addToggleRow(stack, "Auto-add files from directory", key: Defaults.autoAddFromDirectory)
        addRow(stack, "Sort order:", NSPopUpButton().configured { $0.addItems(withTitles: ["Name (ascending)", "Name (descending)", "Date modified", "File size"]) })
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class VideoPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addSectionHeader(stack, "Display")
        addRow(stack, "Default aspect ratio:", NSPopUpButton().configured { $0.addItems(withTitles: ["Auto", "4:3", "16:9", "16:10", "2.35:1", "2.39:1"]) })
        addRow(stack, "Default window size:", NSPopUpButton().configured { $0.addItems(withTitles: ["Fit to Screen", "Original Size", "Half Size", "Double Size", "50%", "75%", "150%", "200%"]) })
        addRow(stack, "Fill screen mode:", NSPopUpButton().configured { $0.addItems(withTitles: ["Stretch to Fill", "Crop to Fill"]) })

        addSectionHeader(stack, "HDR")
        addRow(stack, "HDR tone mapping:", NSPopUpButton().configured { $0.addItems(withTitles: ["System Default", "Always HDR", "Force SDR"]) })

        addSectionHeader(stack, "Video Equalizer Defaults")
        addSliderRow(stack, "Brightness:", min: -0.5, max: 0.5, value: 0, key: "video.defaultBrightness")
        addSliderRow(stack, "Contrast:", min: 0.5, max: 2.0, value: 1.0, key: "video.defaultContrast")
        addSliderRow(stack, "Saturation:", min: 0, max: 2.0, value: 1.0, key: "video.defaultSaturation")

        addSectionHeader(stack, "Screenshot")
        addRow(stack, "Format:", NSPopUpButton().configured { $0.addItems(withTitles: ["PNG", "JPEG", "TIFF"]) })
        addRow(stack, "Save to:", NSPopUpButton().configured { $0.addItems(withTitles: ["Desktop", "Pictures", "Downloads", "Custom…"]) })
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
        addRow(stack, "Audio passthrough:", NSPopUpButton().configured { $0.addItems(withTitles: ["Auto-detect", "Always On", "Off"]) })

        addSectionHeader(stack, "Equalizer")
        addRow(stack, "Default EQ preset:", NSPopUpButton().configured { $0.addItems(withTitles: AudioEqualizer.presets.map { $0.name }) })

        addSectionHeader(stack, "Audio Processing")
        addToggleRow(stack, "Enable compressor (night mode)", key: "audio.compressorEnabled")
        addToggleRow(stack, "Enable spatializer (headphone surround)", key: "audio.spatializerEnabled")
        addSliderRow(stack, "Stereo width:", min: 0, max: 200, value: 100, key: "audio.stereoWidth")

        addSectionHeader(stack, "Normalization")
        addToggleRow(stack, "Enable loudness normalization", key: "audio.normalizationEnabled")
        addSliderRow(stack, "Target loudness (LUFS):", min: -24, max: -6, value: -14, key: Defaults.normalizationTarget)

        addSectionHeader(stack, "Sync")
        addSliderRow(stack, "Audio delay step (ms):", min: 10, max: 500, value: 100, key: "audio.delayStep")
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
        addRow(stack, "Preferred language:", NSPopUpButton().configured { $0.addItems(withTitles: ["Any", "English", "Chinese (Simplified)", "Chinese (Traditional)", "Japanese", "Korean", "Spanish", "French", "German"]) })

        addSectionHeader(stack, "Encoding")
        addRow(stack, "Default encoding:", NSPopUpButton().configured { $0.addItems(withTitles: ["UTF-8", "Auto-detect", "GBK (Chinese)", "Shift-JIS (Japanese)", "EUC-KR (Korean)", "ISO-8859-1 (Latin)", "Windows-1252 (Western)"]) })

        addSectionHeader(stack, "Appearance")
        addRow(stack, "Font:", NSPopUpButton().configured { $0.addItems(withTitles: ["System Default", "Helvetica Neue", "Arial", "SF Pro", "PingFang SC"]) })
        addSliderRow(stack, "Font size:", min: 12, max: 60, value: 24, key: Defaults.subtitleFontSize)
        addRow(stack, "Text color:", NSPopUpButton().configured { $0.addItems(withTitles: ["White", "Yellow", "Green", "Cyan"]) })
        addRow(stack, "Outline:", NSPopUpButton().configured { $0.addItems(withTitles: ["Black outline", "Shadow only", "Background box", "None"]) })

        addSectionHeader(stack, "Position")
        addRow(stack, "Display position:", NSPopUpButton().configured { $0.addItems(withTitles: ["Bottom of Video", "Bottom of Screen", "Upper Letterbox", "Lower Letterbox"]) })

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
        addRow(stack, "Control bar:", NSPopUpButton().configured { $0.addItems(withTitles: ["Auto-hide (3 seconds)", "Auto-hide (5 seconds)", "Always Show"]) })

        addSectionHeader(stack, "Time Display")
        addRow(stack, "Time OSD position:", NSPopUpButton().configured { $0.addItems(withTitles: ["Top-left", "Top-center", "Top-right", "Hidden"]) })
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class InputPrefsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private var shortcuts: [(action: String, key: String)] = [
        ("Play / Pause", "Space"),
        ("Seek ±5 seconds", "← / →"),
        ("Seek ±30 seconds", "⇧← / ⇧→"),
        ("Seek ±60 seconds", "⌘← / ⌘→"),
        ("Volume up / down", "↑ / ↓"),
        ("Mute / Unmute", "M"),
        ("Toggle fullscreen", "F"),
        ("Speed -/+ 0.25x", "[ / ]"),
        ("Reset speed 1.0x", "\\"),
        ("A-B loop", "R"),
        ("Open file", "⌘O"),
        ("Keep on top", "⌘T"),
        ("Save screenshot", "⌥⌘S"),
    ]
    private var editingRow: Int? = nil

    override init(frame: NSRect) {
        super.init(frame: frame)

        let stack = makePrefsStack()

        addSectionHeader(stack, "Media Keys")
        addToggleRow(stack, "Enable media keys (Play/Pause, Next, Prev)", key: Defaults.mediaKeyEnabled)

        addSectionHeader(stack, "Escape Key")
        addRow(stack, "Escape key action:", NSPopUpButton().configured { $0.addItems(withTitles: ["Exit Fullscreen", "Close Panel", "Stop Playback"]) })

        addSectionHeader(stack, "Keyboard Shortcuts")
        let hint = NSTextField(labelWithString: "Double-click a shortcut to change it")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(hint)

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
        tableView.doubleAction = #selector(shortcutDoubleClicked)
        tableView.target = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 200).isActive = true
        stack.addArrangedSubview(scrollView)

        let resetBtn = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetShortcuts))
        resetBtn.bezelStyle = .rounded
        stack.addArrangedSubview(resetBtn)

        addSectionHeader(stack, "Mouse")
        addRow(stack, "Single click:", NSPopUpButton().configured { $0.addItems(withTitles: ["Play / Pause", "Nothing"]) })
        addRow(stack, "Double click:", NSPopUpButton().configured { $0.addItems(withTitles: ["Toggle Fullscreen", "Nothing"]) })
        addRow(stack, "Middle click:", NSPopUpButton().configured { $0.addItems(withTitles: ["Mute / Unmute", "Play / Pause", "Nothing"]) })
        addRow(stack, "Right click:", NSPopUpButton().configured { $0.addItems(withTitles: ["Context Menu", "Nothing"]) })

        addSectionHeader(stack, "Scroll Wheel")
        addRow(stack, "Scroll action:", NSPopUpButton().configured { $0.addItems(withTitles: ["Volume", "Seek", "Nothing"]) })
        addSliderRow(stack, "Scroll sensitivity:", min: 1, max: 10, value: 5, key: Defaults.scrollWheelSensitivity)

        addSectionHeader(stack, "Trackpad")
        addRow(stack, "Pinch gesture:", NSPopUpButton().configured { $0.addItems(withTitles: ["Zoom Video", "Resize Window", "Nothing"]) })

        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }

    func numberOfRows(in tableView: NSTableView) -> Int { shortcuts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text: String
        if tableColumn?.identifier.rawValue == "action" {
            text = shortcuts[row].action
        } else {
            if editingRow == row {
                text = "⌨ Press key…"
            } else {
                text = shortcuts[row].key
            }
        }
        let label = NSTextField(labelWithString: text)
        label.font = tableColumn?.identifier.rawValue == "key"
            ? .monospacedSystemFont(ofSize: 12, weight: .medium)
            : .systemFont(ofSize: 12)
        if editingRow == row && tableColumn?.identifier.rawValue == "key" {
            label.textColor = .systemBlue
        }
        return label
    }

    @objc private func shortcutDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        editingRow = row
        tableView.reloadData()

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let editing = self.editingRow else { return event }
            var parts: [String] = []
            if event.modifierFlags.contains(.control) { parts.append("⌃") }
            if event.modifierFlags.contains(.option) { parts.append("⌥") }
            if event.modifierFlags.contains(.shift) { parts.append("⇧") }
            if event.modifierFlags.contains(.command) { parts.append("⌘") }
            let char = event.charactersIgnoringModifiers?.uppercased() ?? ""
            parts.append(char)
            self.shortcuts[editing].key = parts.joined()
            self.editingRow = nil
            self.tableView.reloadData()
            return nil
        }
    }

    @objc private func resetShortcuts() {
        shortcuts = [
            ("Play / Pause", "Space"),
            ("Seek ±5 seconds", "← / →"),
            ("Seek ±30 seconds", "⇧← / ⇧→"),
            ("Seek ±60 seconds", "⌘← / ⌘→"),
            ("Volume up / down", "↑ / ↓"),
            ("Mute / Unmute", "M"),
            ("Toggle fullscreen", "F"),
            ("Speed -/+ 0.25x", "[ / ]"),
            ("Reset speed 1.0x", "\\"),
            ("A-B loop", "R"),
            ("Open file", "⌘O"),
            ("Keep on top", "⌘T"),
            ("Save screenshot", "⌥⌘S"),
        ]
        editingRow = nil
        tableView.reloadData()
    }
}

class CastPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addSectionHeader(stack, "Connection")
        addRow(stack, "Default behavior:", NSPopUpButton().configured { $0.addItems(withTitles: ["Ask every time", "Auto-connect to last device"]) })
        addToggleRow(stack, "Auto-disconnect on window close", key: Defaults.autoDisconnectOnClose)
        addToggleRow(stack, "Resume local playback on disconnect", key: Defaults.resumeLocalOnDisconnect)

        addSectionHeader(stack, "AirPlay")
        addRow(stack, "Show AirPlay button:", NSPopUpButton().configured { $0.addItems(withTitles: ["Always", "When device available", "Never"]) })

        addSectionHeader(stack, "Chromecast")
        addRow(stack, "Transcoding quality:", NSPopUpButton().configured { $0.addItems(withTitles: ["Low (720p)", "Medium (1080p)", "High (4K)"]) })

        addSectionHeader(stack, "DLNA")
        addRow(stack, "Transcoding quality:", NSPopUpButton().configured { $0.addItems(withTitles: ["Low (720p)", "Medium (1080p)", "High (4K)"]) })
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
        // Wrap in a flipped container so content starts from the top
        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -12),
        ])

        let scrollView = NSScrollView()
        scrollView.documentView = container
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
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
        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 12)
        lbl.lineBreakMode = .byTruncatingTail
        lbl.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        lbl.widthAnchor.constraint(equalToConstant: 220).isActive = true
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(control)
        stack.addArrangedSubview(row)
    }

    func addToggleRow(_ stack: NSStackView, _ label: String, key: String) {
        let toggle = NSSwitch()
        toggle.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
        addRow(stack, label, toggle)
    }

    func addSliderRow(_ stack: NSStackView, _ label: String, min: Double, max: Double, value: Double, key: String) {
        let slider = NSSlider()
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = UserDefaults.standard.double(forKey: key) != 0 ? UserDefaults.standard.double(forKey: key) : value
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        addRow(stack, label, slider)
    }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

extension NSPopUpButton {
    func configured(_ block: (NSPopUpButton) -> Void) -> NSPopUpButton {
        block(self)
        isEnabled = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        return self
    }
}
