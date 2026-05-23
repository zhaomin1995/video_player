import Cocoa

class PreferencesWindowController: NSWindowController {
    private let tabView = NSTabView()

    private let tabs: [(String, String, NSView)] = [
        ("General", "gearshape", GeneralPrefsView()),
        ("Media Open", "doc.badge.plus", MediaOpenPrefsView()),
        ("Playback", "play.circle", PlaybackPrefsView()),
        ("Playlist", "list.bullet", PlaylistPrefsView()),
        ("Video", "film", VideoPrefsView()),
        ("Audio", "speaker.wave.3", AudioPrefsView()),
        ("Subtitle", "captions.bubble", SubtitlePrefsView()),
        ("Full Screen", "arrow.up.left.and.arrow.down.right", FullScreenPrefsView()),
        ("Keyboard", "keyboard", KeyboardPrefsView()),
        ("Mouse", "computermouse", MousePrefsView()),
        ("Cast", "tv", CastPrefsView()),
    ]

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
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
        window?.toolbar = toolbar

        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .noTabsNoBorder
        window?.contentView?.addSubview(tabView)

        for (i, (name, _, view)) in tabs.enumerated() {
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
        for (i, (name, _, _)) in tabs.enumerated() {
            if name == sender.itemIdentifier.rawValue {
                tabView.selectTabViewItem(at: i)
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
        item.image = NSImage(systemSymbolName: tab.1, accessibilityDescription: tab.0)
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
        addRow(stack, "Theme:", NSPopUpButton().configured { $0.addItems(withTitles: ["System", "Dark", "Light"]) })
        addToggleRow(stack, "Transparent title bar", key: Defaults.transparentTitleBar)
        addToggleRow(stack, "Resume playback position", key: Defaults.resumePlayback)
        addToggleRow(stack, "Quit when last window closed", key: Defaults.quitOnLastWindowClosed)
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class MediaOpenPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addRow(stack, "Default engine:", NSPopUpButton().configured { $0.addItems(withTitles: ["Auto", "AVPlayer", "FFmpeg"]) })
        addToggleRow(stack, "Auto-find series files", key: Defaults.autoFindSeriesFiles)
        addToggleRow(stack, "Auto-load subtitle files", key: Defaults.autoLoadSubtitles)
        addToggleRow(stack, "Auto-load next file in folder", key: Defaults.autoLoadNextFile)
        addToggleRow(stack, "Open in new window", key: Defaults.openInNewWindow)
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class PlaybackPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addSliderRow(stack, "Default speed:", min: 0.25, max: 4.0, value: 1.0, key: Defaults.defaultSpeed)
        addSliderRow(stack, "Short seek (s):", min: 1, max: 30, value: 5, key: Defaults.shortSeekInterval)
        addSliderRow(stack, "Long seek (s):", min: 5, max: 120, value: 30, key: Defaults.longSeekInterval)
        addToggleRow(stack, "Auto-play on open", key: Defaults.autoPlayOnOpen)
        addRow(stack, "When media ends:", NSPopUpButton().configured { $0.addItems(withTitles: ["Do Nothing", "Close", "Play Next", "Loop"]) })
        addSliderRow(stack, "A-B loop gap (s):", min: 0, max: 5, value: 0, key: Defaults.abLoopGap)
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class PlaylistPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addRow(stack, "Repeat mode:", NSPopUpButton().configured { $0.addItems(withTitles: ["Off", "One", "All"]) })
        addToggleRow(stack, "Shuffle", key: Defaults.shuffle)
        addRow(stack, "When playlist ends:", NSPopUpButton().configured { $0.addItems(withTitles: ["Do Nothing", "Close Window", "Quit"]) })
        addToggleRow(stack, "Auto-add files from directory", key: Defaults.autoAddFromDirectory)
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class VideoPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addRow(stack, "Default aspect ratio:", NSPopUpButton().configured { $0.addItems(withTitles: ["Auto", "4:3", "16:9", "16:10", "2.35:1"]) })
        addRow(stack, "Default size:", NSPopUpButton().configured { $0.addItems(withTitles: ["Fit to Screen", "Original", "50%", "200%"]) })
        addRow(stack, "Screenshot format:", NSPopUpButton().configured { $0.addItems(withTitles: ["PNG", "JPEG", "TIFF"]) })
        addRow(stack, "HDR tone mapping:", NSPopUpButton().configured { $0.addItems(withTitles: ["System", "Always HDR", "Force SDR"]) })
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class AudioPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addSliderRow(stack, "Default volume:", min: 0, max: 1, value: 1, key: Defaults.defaultVolume)
        addToggleRow(stack, "Allow extended volume (>100%)", key: Defaults.extendedVolume)
        addRow(stack, "Passthrough:", NSPopUpButton().configured { $0.addItems(withTitles: ["Auto-detect", "Always On", "Off"]) })
        addRow(stack, "Default EQ preset:", NSPopUpButton().configured { $0.addItems(withTitles: AudioEqualizer.presets.map { $0.name }) })
        addSliderRow(stack, "Normalization (LUFS):", min: -24, max: -6, value: -14, key: Defaults.normalizationTarget)
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class SubtitlePrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addToggleRow(stack, "Auto-load embedded subtitles", key: Defaults.autoLoadEmbedded)
        addToggleRow(stack, "Auto-load external subtitle files", key: Defaults.autoLoadExternal)
        addRow(stack, "Default encoding:", NSPopUpButton().configured { $0.addItems(withTitles: ["UTF-8", "GBK", "Shift-JIS", "EUC-KR", "ISO-8859-1"]) })
        addSliderRow(stack, "Font size:", min: 12, max: 48, value: 24, key: Defaults.subtitleFontSize)
        addRow(stack, "Position:", NSPopUpButton().configured { $0.addItems(withTitles: ["Bottom of Video", "Bottom of Screen", "Letterbox"]) })
        addSliderRow(stack, "Delay step (s):", min: 0.05, max: 1.0, value: 0.1, key: Defaults.subtitleDelayStep)
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class FullScreenPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addToggleRow(stack, "Auto-enter fullscreen on open", key: Defaults.autoEnterFullscreen)
        addToggleRow(stack, "Pause when exiting fullscreen", key: Defaults.pauseOnExitFullscreen)
        addToggleRow(stack, "Start playing when entering fullscreen", key: Defaults.playOnEnterFullscreen)
        addToggleRow(stack, "Black out other screens", key: Defaults.blackOutOtherScreens)
        addRow(stack, "Control bar:", NSPopUpButton().configured { $0.addItems(withTitles: ["Auto-hide", "Always Show"]) })
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class KeyboardPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addToggleRow(stack, "Enable media keys (Play/Pause, Next, Prev)", key: Defaults.mediaKeyEnabled)
        addRow(stack, "Escape key:", NSPopUpButton().configured { $0.addItems(withTitles: ["Exit Fullscreen", "Close Panel", "Stop Playback"]) })

        let note = NSTextField(wrappingLabelWithString: "Keyboard shortcuts can be customized in future versions. Current shortcuts: Space (play/pause), Arrows (seek/volume), F (fullscreen), M (mute), S (subtitles), R (A-B loop), [ ] (speed).")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(note)
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class MousePrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addRow(stack, "Single click:", NSPopUpButton().configured { $0.addItems(withTitles: ["Play/Pause", "Nothing"]) })
        addRow(stack, "Double click:", NSPopUpButton().configured { $0.addItems(withTitles: ["Fullscreen", "Nothing"]) })
        addRow(stack, "Middle click:", NSPopUpButton().configured { $0.addItems(withTitles: ["Mute", "Pause", "Nothing"]) })
        addRow(stack, "Scroll wheel:", NSPopUpButton().configured { $0.addItems(withTitles: ["Volume", "Seek", "Nothing"]) })
        embed(stack)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class CastPrefsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = makePrefsStack()
        addRow(stack, "Default behavior:", NSPopUpButton().configured { $0.addItems(withTitles: ["Ask", "Auto-connect Last"]) })
        addRow(stack, "Chromecast quality:", NSPopUpButton().configured { $0.addItems(withTitles: ["Low", "Medium", "High"]) })
        addRow(stack, "DLNA quality:", NSPopUpButton().configured { $0.addItems(withTitles: ["Low", "Medium", "High"]) })
        addToggleRow(stack, "Auto-disconnect on window close", key: Defaults.autoDisconnectOnClose)
        addToggleRow(stack, "Resume local playback on disconnect", key: Defaults.resumeLocalOnDisconnect)
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
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    func addRow(_ stack: NSStackView, _ label: String, _ control: NSView) {
        let row = NSStackView()
        row.orientation = .horizontal
        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 12)
        lbl.widthAnchor.constraint(equalToConstant: 180).isActive = true
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

extension NSPopUpButton {
    func configured(_ block: (NSPopUpButton) -> Void) -> NSPopUpButton {
        block(self)
        return self
    }
}
