import Cocoa

class VideoPanelView: NSView {
    private let brightnessSlider = NSSlider()
    private let contrastSlider = NSSlider()
    private let saturationSlider = NSSlider()
    private let sharpnessSlider = NSSlider()
    private let gammaSlider = NSSlider()
    private let resetButton = NSButton()

    var onBrightnessChanged: ((Float) -> Void)?
    var onContrastChanged: ((Float) -> Void)?
    var onSaturationChanged: ((Float) -> Void)?
    var onSharpnessChanged: ((Float) -> Void)?
    var onGammaChanged: ((Float) -> Void)?
    var onReset: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let title = NSTextField(labelWithString: "Video Equalizer")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .white
        stack.addArrangedSubview(title)

        stack.addArrangedSubview(makeSliderRow("Brightness", brightnessSlider, min: -0.5, max: 0.5, value: 0, action: #selector(brightnessChanged)))
        stack.addArrangedSubview(makeSliderRow("Contrast", contrastSlider, min: 0.5, max: 2.0, value: 1.0, action: #selector(contrastChanged)))
        stack.addArrangedSubview(makeSliderRow("Saturation", saturationSlider, min: 0, max: 2.0, value: 1.0, action: #selector(saturationChanged)))
        stack.addArrangedSubview(makeSliderRow("Sharpness", sharpnessSlider, min: 0, max: 2.0, value: 0, action: #selector(sharpnessChanged)))
        stack.addArrangedSubview(makeSliderRow("Gamma", gammaSlider, min: 0.5, max: 2.0, value: 1.0, action: #selector(gammaChanged)))

        resetButton.title = "Reset"
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetClicked)
        stack.addArrangedSubview(resetButton)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    private func makeSliderRow(_ label: String, _ slider: NSSlider, min: Double, max: Double, value: Double, action: Selector) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        let lbl = NSTextField(labelWithString: label)
        lbl.textColor = .white
        lbl.font = .systemFont(ofSize: 11)
        lbl.widthAnchor.constraint(equalToConstant: 80).isActive = true
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = value
        slider.isContinuous = true
        slider.target = self
        slider.action = action
        let valLabel = NSTextField(labelWithString: String(format: "%.2f", value))
        valLabel.textColor = .secondaryLabelColor
        valLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        valLabel.widthAnchor.constraint(equalToConstant: 35).isActive = true
        valLabel.tag = label.hashValue
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(valLabel)
        return row
    }

    @objc private func brightnessChanged() { onBrightnessChanged?(Float(brightnessSlider.doubleValue)) }
    @objc private func contrastChanged() { onContrastChanged?(Float(contrastSlider.doubleValue)) }
    @objc private func saturationChanged() { onSaturationChanged?(Float(saturationSlider.doubleValue)) }
    @objc private func sharpnessChanged() { onSharpnessChanged?(Float(sharpnessSlider.doubleValue)) }
    @objc private func gammaChanged() { onGammaChanged?(Float(gammaSlider.doubleValue)) }
    @objc private func resetClicked() {
        brightnessSlider.doubleValue = 0
        contrastSlider.doubleValue = 1
        saturationSlider.doubleValue = 1
        sharpnessSlider.doubleValue = 0
        gammaSlider.doubleValue = 1
        onReset?()
    }
}
