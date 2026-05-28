import Cocoa

class OSDView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let effectView = NSVisualEffectView()
    private var hideTimer: Timer?

    private let barContainer = NSView()
    private let barFill = NSView()
    private let barIcon = NSImageView()
    private var barFillWidthConstraint: NSLayoutConstraint?
    private let barWidth: CGFloat = 180

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
        alphaValue = 0

        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true
        // Subtle hairline border lifts the OSD off bright video frames where
        // the vibrancy alone disappears against high-key content.
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        effectView.layer?.borderWidth = 0.5
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(label)

        // Bar overlay for volume/brightness
        barContainer.wantsLayer = true
        barContainer.translatesAutoresizingMaskIntoConstraints = false
        barContainer.isHidden = true
        effectView.addSubview(barContainer)

        barIcon.translatesAutoresizingMaskIntoConstraints = false
        barIcon.contentTintColor = .white
        barContainer.addSubview(barIcon)

        let barTrack = NSView()
        barTrack.wantsLayer = true
        barTrack.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        barTrack.layer?.cornerRadius = 2.5
        barTrack.translatesAutoresizingMaskIntoConstraints = false
        barContainer.addSubview(barTrack)

        barFill.wantsLayer = true
        barFill.layer?.backgroundColor = NSColor.white.cgColor
        barFill.layer?.cornerRadius = 2.5
        barFill.translatesAutoresizingMaskIntoConstraints = false
        barTrack.addSubview(barFill)

        let fillWidth = barFill.widthAnchor.constraint(equalToConstant: 0)
        barFillWidthConstraint = fillWidth

        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),

            label.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),

            barContainer.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 8),
            barContainer.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -8),
            barContainer.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 12),
            barContainer.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -12),
            barContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: barWidth),
            barContainer.heightAnchor.constraint(equalToConstant: 20),

            barIcon.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
            barIcon.centerYAnchor.constraint(equalTo: barContainer.centerYAnchor),
            barIcon.widthAnchor.constraint(equalToConstant: 18),
            barIcon.heightAnchor.constraint(equalToConstant: 18),

            barTrack.leadingAnchor.constraint(equalTo: barIcon.trailingAnchor, constant: 8),
            barTrack.trailingAnchor.constraint(equalTo: barContainer.trailingAnchor),
            barTrack.centerYAnchor.constraint(equalTo: barContainer.centerYAnchor),
            barTrack.heightAnchor.constraint(equalToConstant: 5),

            barFill.leadingAnchor.constraint(equalTo: barTrack.leadingAnchor),
            barFill.topAnchor.constraint(equalTo: barTrack.topAnchor),
            barFill.bottomAnchor.constraint(equalTo: barTrack.bottomAnchor),
            fillWidth,
        ])
    }

    func show(message: String, duration: TimeInterval = 1.5) {
        label.stringValue = message
        label.isHidden = false
        barContainer.isHidden = true
        animateIn()
        scheduleHide(after: duration)
    }

    /// Show an animated bar overlay (for volume, brightness, seek progress).
    /// The fill animates between successive updates for a smooth "drawing"
    /// feel instead of a step change.
    func showBar(icon: String, fraction: Double, duration: TimeInterval = 1.0) {
        label.isHidden = true
        barContainer.isHidden = false
        barIcon.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)

        let trackWidth = barWidth - 26
        let newWidth = max(0, min(trackWidth, trackWidth * fraction))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            barFillWidthConstraint?.animator().constant = newWidth
        }
        barContainer.needsLayout = true

        animateIn()
        scheduleHide(after: duration)
    }

    private func animateIn() {
        hideTimer?.invalidate()
        // Slight scale-in pop matches Apple HUD style. The transform target
        // is the layer (not autoresizing constants), so we set it directly
        // without going through the autolayout system.
        if alphaValue < 0.5 {
            layer?.transform = CATransform3DMakeScale(0.92, 0.92, 1)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            self.animator().alphaValue = 1.0
            self.layer?.transform = CATransform3DIdentity
        }
    }

    private func scheduleHide(after duration: TimeInterval) {
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self?.animator().alphaValue = 0.0
            }
        }
    }
}
