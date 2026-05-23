import Cocoa

class WelcomeView: NSView {
    private let iconView = NSView()
    private let playSymbol = NSImageView()

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
        layer?.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor

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

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 120),
            iconView.heightAnchor.constraint(equalToConstant: 120),

            playSymbol.centerXAnchor.constraint(equalTo: iconView.centerXAnchor, constant: 4),
            playSymbol.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
        ])
    }

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
