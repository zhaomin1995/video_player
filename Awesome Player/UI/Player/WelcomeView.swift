/// Welcome/empty-state view shown before a file is opened. Radial gradient
/// (dark center, lighter edges) draws the eye toward the centered play
/// glyph; quick-action buttons + a recent-files strip live below.
import Cocoa

/// NSButton subclass with a typed URL payload — replaces an earlier
/// objc_setAssociatedObject hack that stashed the URL on the button via the
/// Obj-C runtime.
final class RecentChipButton: NSButton {
    var recentURL: URL?
}

class WelcomeView: NSView {
    private let iconView = NSView()
    private let playSymbol = NSImageView()
    private let hintLabel = NSTextField(labelWithString: "")
    private let openFileButton = NSButton(title: "", target: nil, action: nil)
    private let openURLButton = NSButton(title: "", target: nil, action: nil)
    private let recentTitle = NSTextField(labelWithString: "")
    private let recentStack = NSStackView()
    var onFileDropped: ((URL) -> Void)?
    var onRecentClicked: ((URL) -> Void)?
    var onOpenFileClicked: (() -> Void)?
    var onOpenURLClicked: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        // The recent-files strip and labels bake L() text at init time; rebuild
        // when the language flips so the welcome view doesn't show stale strings.
        NotificationCenter.default.addObserver(self, selector: #selector(refreshLocalizedText),
                                                name: .languageDidChange, object: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let url = urls.first else { return false }
        onFileDropped?(url)
        return true
    }

    /// Pulls the latest recent documents and rebuilds the bottom strip. Called
    /// from the controller after a file open so the list stays current without
    /// the welcome view subscribing to NSDocumentController KVO.
    func refreshRecents() {
        recentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Pull from the app's own recent-files store (RecentDocumentsMenuDelegate
        // key). NSDocumentController.recentDocumentURLs is unused — the player
        // doesn't register as a document app, so AppKit's recents list is empty.
        let paths = (UserDefaults.standard.stringArray(forKey: "AwesomePlayer_RecentFiles") ?? [])
            .prefix(4)
            .map { URL(fileURLWithPath: $0) }
        recentTitle.isHidden = paths.isEmpty
        for url in paths {
            recentStack.addArrangedSubview(makeRecentChip(for: url))
        }
    }

    private func setupViews() {
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
        layer?.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor

        // Icon — same Movist-style rounded square as before
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 28
        iconView.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
        iconView.layer?.shadowColor = NSColor.black.cgColor
        iconView.layer?.shadowOffset = CGSize(width: 0, height: -4)
        iconView.layer?.shadowRadius = 20
        iconView.layer?.shadowOpacity = 0.5
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .medium)
        let image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")?.withSymbolConfiguration(config)
        playSymbol.image = image
        playSymbol.contentTintColor = NSColor(calibratedRed: 0.55, green: 0.65, blue: 0.95, alpha: 1)
        playSymbol.translatesAutoresizingMaskIntoConstraints = false
        iconView.addSubview(playSymbol)

        // Hint
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = NSColor(white: 0.7, alpha: 1)
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        // Quick action buttons
        for b in [openFileButton, openURLButton] {
            b.bezelStyle = .rounded
            b.translatesAutoresizingMaskIntoConstraints = false
        }
        openFileButton.target = self
        openFileButton.action = #selector(openFileClicked)
        openURLButton.target = self
        openURLButton.action = #selector(openURLClicked)

        let actionStack = NSStackView(views: [openFileButton, openURLButton])
        actionStack.orientation = .horizontal
        actionStack.spacing = 12
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionStack)

        // Recent files strip
        recentTitle.font = .systemFont(ofSize: 11, weight: .medium)
        recentTitle.textColor = NSColor(white: 0.55, alpha: 1)
        recentTitle.alignment = .center
        recentTitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(recentTitle)

        recentStack.orientation = .horizontal
        recentStack.spacing = 8
        recentStack.alignment = .centerY
        recentStack.distribution = .equalSpacing
        recentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(recentStack)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -50),
            iconView.widthAnchor.constraint(equalToConstant: 120),
            iconView.heightAnchor.constraint(equalToConstant: 120),

            playSymbol.centerXAnchor.constraint(equalTo: iconView.centerXAnchor, constant: 4),
            playSymbol.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            hintLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 18),
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            actionStack.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 18),
            actionStack.centerXAnchor.constraint(equalTo: centerXAnchor),

            recentTitle.topAnchor.constraint(equalTo: actionStack.bottomAnchor, constant: 36),
            recentTitle.centerXAnchor.constraint(equalTo: centerXAnchor),

            recentStack.topAnchor.constraint(equalTo: recentTitle.bottomAnchor, constant: 10),
            recentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            recentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            recentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
        ])

        refreshLocalizedText()
        refreshRecents()
    }

    @objc private func refreshLocalizedText() {
        hintLabel.stringValue = L("Drop a video here, or pick one below")
        openFileButton.title = L("Open File…")
        openURLButton.title = L("Open URL…")
        recentTitle.stringValue = L("RECENT")
        setAccessibilityLabel(L("Drop video file here to play"))
        setAccessibilityRole(.group)
    }

    @objc private func openFileClicked() { onOpenFileClicked?() }
    @objc private func openURLClicked() { onOpenURLClicked?() }

    /// Small pill rendering one recent-file URL. Truncated middle so the
    /// parent dir and filename both survive when the path is long.
    private func makeRecentChip(for url: URL) -> NSView {
        let chip = RecentChipButton()
        chip.recentURL = url
        chip.title = url.lastPathComponent
        chip.toolTip = url.path
        chip.bezelStyle = .inline
        chip.lineBreakMode = .byTruncatingMiddle
        chip.target = self
        chip.action = #selector(recentChipClicked(_:))
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.widthAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
        return chip
    }

    @objc private func recentChipClicked(_ sender: RecentChipButton) {
        guard let url = sender.recentURL else { return }
        onRecentClicked?(url)
    }

    /// Rebuild the radial gradient on every updateLayer pass so it tracks
    /// resize and theme change.
    override func updateLayer() {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.frame = bounds
        gradient.colors = [
            NSColor(white: 0.06, alpha: 1).cgColor,
            NSColor(white: 0.10, alpha: 1).cgColor,
            NSColor(white: 0.16, alpha: 1).cgColor,
            NSColor(white: 0.22, alpha: 1).cgColor,
        ]
        gradient.locations = [0.0, 0.3, 0.7, 1.0]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        layer?.sublayers?.filter { $0 is CAGradientLayer }.forEach { $0.removeFromSuperlayer() }
        layer?.insertSublayer(gradient, at: 0)
    }

    override func layout() {
        super.layout()
        layer?.sublayers?.first(where: { $0 is CAGradientLayer })?.frame = bounds
    }
}
