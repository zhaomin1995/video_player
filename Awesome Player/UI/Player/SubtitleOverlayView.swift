import Cocoa

class SubtitleOverlayView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true

        let fontSize = CGFloat(UserDefaults.standard.double(forKey: Defaults.subtitleFontSize))
        let fontIndex = UserDefaults.standard.integer(forKey: Defaults.subtitleFont)
        let fontNames = ["", "HelveticaNeue", "Arial", "SFProText-Regular", "PingFangSC-Regular"]
        if fontIndex > 0 && fontIndex < fontNames.count,
           let font = NSFont(name: fontNames[fontIndex], size: fontSize > 0 ? fontSize : 24) {
            label.font = font
        } else {
            label.font = .systemFont(ofSize: fontSize > 0 ? fontSize : 24, weight: .medium)
        }

        let colorIndex = UserDefaults.standard.integer(forKey: Defaults.subtitleColor)
        let colors: [NSColor] = [.white, .yellow, .green, .cyan]
        label.textColor = colorIndex < colors.count ? colors[colorIndex] : .white
        label.alignment = .center
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.maximumNumberOfLines = 3

        label.wantsLayer = true
        label.layer?.shadowColor = NSColor.black.cgColor
        label.layer?.shadowOffset = CGSize(width: 0, height: -1)
        label.layer?.shadowRadius = 3
        label.layer?.shadowOpacity = 0.8

        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Observe subtitle preference changes for live updates
        for key in [Defaults.subtitleFont, Defaults.subtitleFontSize, Defaults.subtitleColor] {
            UserDefaults.standard.addObserver(self, forKeyPath: key, options: .new, context: nil)
        }
    }

    deinit {
        for key in [Defaults.subtitleFont, Defaults.subtitleFontSize, Defaults.subtitleColor] {
            UserDefaults.standard.removeObserver(self, forKeyPath: key)
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        refreshAppearance()
    }

    func refreshAppearance() {
        let fontSize = CGFloat(UserDefaults.standard.double(forKey: Defaults.subtitleFontSize))
        let fontIndex = UserDefaults.standard.integer(forKey: Defaults.subtitleFont)
        let fontNames = ["", "HelveticaNeue", "Arial", "SFProText-Regular", "PingFangSC-Regular"]
        if fontIndex > 0 && fontIndex < fontNames.count,
           let font = NSFont(name: fontNames[fontIndex], size: fontSize > 0 ? fontSize : 24) {
            label.font = font
        } else {
            label.font = .systemFont(ofSize: fontSize > 0 ? fontSize : 24, weight: .medium)
        }

        let colorIndex = UserDefaults.standard.integer(forKey: Defaults.subtitleColor)
        let colors: [NSColor] = [.white, .yellow, .green, .cyan]
        label.textColor = colorIndex < colors.count ? colors[colorIndex] : .white
    }

    func setText(_ text: String?) {
        if let text = text, !text.isEmpty {
            label.stringValue = text
            isHidden = false
        } else {
            label.stringValue = ""
            isHidden = true
        }
    }

    func setAttributedText(_ text: NSAttributedString?) {
        if let text = text, text.length > 0 {
            label.attributedStringValue = text
            isHidden = false
        } else {
            label.stringValue = ""
            isHidden = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Transparent background
    }
}
