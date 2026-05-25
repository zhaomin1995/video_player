import Cocoa

class VideoEQPanelController: NSWindowController {
    weak var playerViewController: PlayerViewController?

    init() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 280),
                            styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: false)
        window.title = "Video Equalizer"
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        super.init(window: window)
        setupContent()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupContent() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let params: [(String, String, Float, Float, Float)] = [
            ("Brightness", "brightness", 0, 2, 1),
            ("Contrast", "contrast", 0, 2, 1),
            ("Saturation", "saturation", 0, 3, 1),
            ("Hue", "hue", -180, 180, 0),
            ("Gamma", "gamma", 0.01, 10, 1),
        ]

        for (label, id, min, max, def) in params {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            let lbl = NSTextField(labelWithString: label)
            lbl.widthAnchor.constraint(equalToConstant: 80).isActive = true
            let slider = NSSlider(value: Double(def), minValue: Double(min), maxValue: Double(max), target: self, action: #selector(sliderChanged(_:)))
            slider.identifier = NSUserInterfaceItemIdentifier(id)
            slider.widthAnchor.constraint(equalToConstant: 160).isActive = true
            let valLabel = NSTextField(labelWithString: String(format: "%.1f", def))
            valLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
            valLabel.tag = id.hashValue
            row.addArrangedSubview(lbl)
            row.addArrangedSubview(slider)
            row.addArrangedSubview(valLabel)
            stack.addArrangedSubview(row)
        }

        let resetBtn = NSButton(title: "Reset", target: self, action: #selector(resetAll))
        resetBtn.bezelStyle = .rounded
        stack.addArrangedSubview(resetBtn)

        window?.contentView = stack
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let id = sender.identifier?.rawValue,
              let vlc = playerViewController?.vlcEngine else { return }
        let value = Float(sender.doubleValue)
        switch id {
        case "brightness": vlc.setBrightness(value)
        case "contrast": vlc.setContrast(value)
        case "saturation": vlc.setSaturation(value)
        case "hue": vlc.setHue(value)
        case "gamma": vlc.setGamma(value)
        default: break
        }
        updateValueLabel(for: sender)
    }

    private func updateValueLabel(for slider: NSSlider) {
        guard let row = slider.superview as? NSStackView else { return }
        for sub in row.arrangedSubviews {
            if let label = sub as? NSTextField, label.tag == slider.identifier?.rawValue.hashValue ?? 0 {
                label.stringValue = String(format: "%.1f", slider.doubleValue)
                break
            }
        }
    }

    @objc private func resetAll() {
        guard let vlc = playerViewController?.vlcEngine else { return }
        vlc.setVideoAdjust(enabled: false)
        // Reset sliders to defaults
        if let stack = window?.contentView as? NSStackView {
            for row in stack.arrangedSubviews {
                guard let rowStack = row as? NSStackView else { continue }
                for sub in rowStack.arrangedSubviews {
                    if let slider = sub as? NSSlider {
                        switch slider.identifier?.rawValue {
                        case "brightness": slider.doubleValue = 1
                        case "contrast": slider.doubleValue = 1
                        case "saturation": slider.doubleValue = 1
                        case "hue": slider.doubleValue = 0
                        case "gamma": slider.doubleValue = 1
                        default: break
                        }
                        updateValueLabel(for: slider)
                    }
                }
            }
        }
        playerViewController?.showOSD("Video adjustments reset")
    }
}
