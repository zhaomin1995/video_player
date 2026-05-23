import Cocoa

class AudioPanelView: NSView {
    private let trackPopup = NSPopUpButton()
    private let passthroughToggle = NSSwitch()
    private let presetPopup = NSPopUpButton()
    private var eqSliders: [NSSlider] = []
    private var eqLabels: [NSTextField] = []
    private let compressorThreshold = NSSlider()
    private let compressorRatio = NSSlider()
    private let spatializerPopup = NSPopUpButton()
    private let pitchSlider = NSSlider()
    private let delaySlider = NSSlider()

    var onEQChanged: ((Int, Float) -> Void)?
    var onPresetChanged: ((String) -> Void)?
    var onPassthroughToggled: ((Bool) -> Void)?
    var onTrackChanged: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        addSubview(scrollView)

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView

        var yOffset: CGFloat = 0

        // Title
        let title = makeLabel("Audio", size: 14, weight: .semibold)
        addToContent(contentView, view: title, y: &yOffset)

        // Track selection
        addToContent(contentView, view: makeLabel("Track"), y: &yOffset)
        trackPopup.translatesAutoresizingMaskIntoConstraints = false
        trackPopup.addItem(withTitle: "Default")
        addToContent(contentView, view: trackPopup, y: &yOffset, height: 24)

        // Passthrough
        let ptStack = NSStackView()
        ptStack.orientation = .horizontal
        ptStack.translatesAutoresizingMaskIntoConstraints = false
        ptStack.addArrangedSubview(makeLabel("Passthrough"))
        passthroughToggle.target = self
        passthroughToggle.action = #selector(passthroughChanged)
        ptStack.addArrangedSubview(passthroughToggle)
        addToContent(contentView, view: ptStack, y: &yOffset)

        // EQ Preset
        addToContent(contentView, view: makeLabel("Equalizer Preset"), y: &yOffset)
        presetPopup.translatesAutoresizingMaskIntoConstraints = false
        for preset in AudioEqualizer.presets {
            presetPopup.addItem(withTitle: preset.name)
        }
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)
        addToContent(contentView, view: presetPopup, y: &yOffset, height: 24)

        // 10-band EQ sliders
        let frequencies = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
        let eqStack = NSStackView()
        eqStack.orientation = .horizontal
        eqStack.spacing = 4
        eqStack.distribution = .fillEqually
        eqStack.translatesAutoresizingMaskIntoConstraints = false

        for (i, freq) in frequencies.enumerated() {
            let bandStack = NSStackView()
            bandStack.orientation = .vertical
            bandStack.spacing = 2

            let slider = NSSlider()
            slider.isVertical = true
            slider.minValue = -12
            slider.maxValue = 12
            slider.doubleValue = 0
            slider.tag = i
            slider.target = self
            slider.action = #selector(eqSliderChanged(_:))
            slider.heightAnchor.constraint(equalToConstant: 80).isActive = true
            eqSliders.append(slider)

            let label = makeLabel(freq, size: 9)
            label.alignment = .center
            eqLabels.append(label)

            bandStack.addArrangedSubview(slider)
            bandStack.addArrangedSubview(label)
            eqStack.addArrangedSubview(bandStack)
        }
        addToContent(contentView, view: eqStack, y: &yOffset, height: 100)

        // Compressor
        addToContent(contentView, view: makeLabel("Compressor"), y: &yOffset)
        addSliderRow(contentView, label: "Threshold", slider: compressorThreshold, min: -40, max: 0, value: -20, y: &yOffset)
        addSliderRow(contentView, label: "Ratio", slider: compressorRatio, min: 1, max: 20, value: 4, y: &yOffset)

        // Spatializer
        addToContent(contentView, view: makeLabel("Spatializer"), y: &yOffset)
        spatializerPopup.translatesAutoresizingMaskIntoConstraints = false
        for preset in AudioSpatializer.presets {
            spatializerPopup.addItem(withTitle: preset.name)
        }
        addToContent(contentView, view: spatializerPopup, y: &yOffset, height: 24)

        // Pitch
        addSliderRow(contentView, label: "Pitch (semitones)", slider: pitchSlider, min: -12, max: 12, value: 0, y: &yOffset)

        // Delay
        addSliderRow(contentView, label: "Delay (ms)", slider: delaySlider, min: -500, max: 500, value: 0, y: &yOffset)

        contentView.heightAnchor.constraint(equalToConstant: yOffset + 10).isActive = true

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    private func makeLabel(_ text: String, size: CGFloat = 11, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func addToContent(_ content: NSView, view: NSView, y: inout CGFloat, height: CGFloat = 20) {
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: content.topAnchor, constant: y),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.heightAnchor.constraint(equalToConstant: height),
        ])
        y += height + 6
    }

    private func addSliderRow(_ content: NSView, label: String, slider: NSSlider, min: Double, max: Double, value: Double, y: inout CGFloat) {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.translatesAutoresizingMaskIntoConstraints = false
        let lbl = makeLabel(label)
        lbl.widthAnchor.constraint(equalToConstant: 120).isActive = true
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = value
        slider.isContinuous = true
        stack.addArrangedSubview(lbl)
        stack.addArrangedSubview(slider)
        addToContent(content, view: stack, y: &y, height: 22)
    }

    @objc private func eqSliderChanged(_ sender: NSSlider) {
        onEQChanged?(sender.tag, Float(sender.doubleValue))
    }

    @objc private func presetChanged() {
        onPresetChanged?(presetPopup.titleOfSelectedItem ?? "Flat")
    }

    @objc private func passthroughChanged() {
        let isOn = passthroughToggle.state == .on
        onPassthroughToggled?(isOn)
        for slider in eqSliders { slider.isEnabled = !isOn }
        presetPopup.isEnabled = !isOn
        compressorThreshold.isEnabled = !isOn
        compressorRatio.isEnabled = !isOn
        spatializerPopup.isEnabled = !isOn
        pitchSlider.isEnabled = !isOn
    }

    func setTracks(_ names: [String]) {
        trackPopup.removeAllItems()
        trackPopup.addItems(withTitles: names)
    }
}
