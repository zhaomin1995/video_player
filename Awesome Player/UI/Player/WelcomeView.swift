/// Welcome/empty-state view shown before a file is opened. Uses a radial gradient
/// (dark center, lighter edges) to draw the eye inward toward the play icon, styled
/// after Movist Pro's idle screen aesthetic.
import Cocoa

class WelcomeView: NSView {
    private let iconView = NSView()
    private let playSymbol = NSImageView()
    var onFileDropped: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

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

    private func setupViews() {
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
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
        // Soft blue tint to contrast against the dark background without being garish
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

    /// Rebuild the radial gradient whenever the layer needs updating (theme change, etc.).
    /// Gradient radiates from dark center outward to subtly lighter edges, creating
    /// depth without any visible "background image" — purely procedural.
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
        // startPoint at center, endPoint at corner makes it a true radial (not linear)
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)

        // Remove stale gradient layers before inserting a fresh one
        layer?.sublayers?.filter { $0 is CAGradientLayer }.forEach { $0.removeFromSuperlayer() }
        layer?.insertSublayer(gradient, at: 0)
    }

    override func layout() {
        super.layout()
        layer?.sublayers?.first(where: { $0 is CAGradientLayer })?.frame = bounds
    }
}
