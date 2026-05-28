import Cocoa

protocol TitleBarDelegate: AnyObject {
    func titleBarPinToggled(isPinned: Bool)
}

class TitleBarView: NSView {
    weak var delegate: TitleBarDelegate?

    private let titleLabel = NSTextField(labelWithString: "Awesome Player")
    private let pinButton = NSButton()
    private let dvBadge = BadgeView(text: "DV")
    private let hdrBadge = BadgeView(text: "HDR")
    private let codecBadge = BadgeView(text: "")
    private let atmosBadge = BadgeView(text: "Atmos")

    private var isPinned = false
    private let badgeStack = NSStackView()

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
        layer?.backgroundColor = NSColor.clear.cgColor

        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        pinButton.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Keep on top")
        pinButton.isBordered = false
        pinButton.bezelStyle = .accessoryBarAction
        pinButton.contentTintColor = .secondaryLabelColor
        pinButton.target = self
        pinButton.action = #selector(pinClicked)
        pinButton.translatesAutoresizingMaskIntoConstraints = false
        pinButton.setButtonType(.toggle)
        pinButton.setAccessibilityLabel(L("Keep window on top"))
        addSubview(pinButton)

        dvBadge.isHidden = true
        hdrBadge.isHidden = true
        codecBadge.isHidden = true
        atmosBadge.isHidden = true

        badgeStack.orientation = .horizontal
        badgeStack.spacing = 4
        badgeStack.addArrangedSubview(dvBadge)
        badgeStack.addArrangedSubview(hdrBadge)
        badgeStack.addArrangedSubview(atmosBadge)
        badgeStack.addArrangedSubview(codecBadge)
        badgeStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeStack)

        NSLayoutConstraint.activate([
            pinButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 80),
            pinButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 20),
            pinButton.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: pinButton.trailingAnchor, constant: 8),

            badgeStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            badgeStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeStack.leadingAnchor, constant: -8),
        ])
    }

    @objc private func pinClicked() {
        isPinned.toggle()
        pinButton.contentTintColor = isPinned ? .systemBlue : .secondaryLabelColor
        delegate?.titleBarPinToggled(isPinned: isPinned)
    }

    func setTitle(_ title: String) {
        titleLabel.stringValue = title
    }

    func updateBadges(isDolbyVision: Bool, isHDR: Bool, codecName: String?, isAtmos: Bool) {
        dvBadge.isHidden = !isDolbyVision
        hdrBadge.isHidden = !isHDR || isDolbyVision
        atmosBadge.isHidden = !isAtmos

        if let codec = codecName, !codec.isEmpty {
            codecBadge.setText(codec)
            codecBadge.isHidden = false
        } else {
            codecBadge.isHidden = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Transparent background — blends with video
    }
}

class BadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor

        label.stringValue = text
        label.font = .systemFont(ofSize: 9, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])

        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setText(_ text: String) {
        label.stringValue = text
    }
}
