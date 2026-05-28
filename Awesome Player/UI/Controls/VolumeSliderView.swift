import Cocoa

class VolumeSliderView: NSView {
    var onVolumeChanged: ((Float) -> Void)?

    private let muteButton = NSButton()
    private let slider = NSSlider()
    private var isMuted = false
    private var savedVolume: Float = 1.0

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
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        muteButton.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Mute")
        muteButton.isBordered = false
        muteButton.contentTintColor = .white
        muteButton.target = self
        muteButton.action = #selector(muteClicked)
        muteButton.widthAnchor.constraint(equalToConstant: 20).isActive = true
        muteButton.setAccessibilityLabel(L("Mute / Unmute"))

        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = 1.0
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true
        slider.setAccessibilityLabel(L("Volume"))

        stack.addArrangedSubview(muteButton)
        stack.addArrangedSubview(slider)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @objc private func muteClicked() {
        isMuted.toggle()
        updateMuteIcon()
        if isMuted {
            savedVolume = Float(slider.doubleValue)
            onVolumeChanged?(0)
        } else {
            onVolumeChanged?(savedVolume)
        }
    }

    @objc private func sliderChanged() {
        let volume = Float(slider.doubleValue)
        isMuted = volume == 0
        updateMuteIcon()
        onVolumeChanged?(volume)
    }

    func setVolume(_ volume: Float) {
        slider.doubleValue = Double(volume)
        isMuted = volume == 0
        updateMuteIcon()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        updateMuteIcon()
    }

    private func updateMuteIcon() {
        let symbol: String
        if isMuted || slider.doubleValue == 0 {
            symbol = "speaker.slash.fill"
        } else if slider.doubleValue < 0.33 {
            symbol = "speaker.wave.1.fill"
        } else if slider.doubleValue < 0.66 {
            symbol = "speaker.wave.2.fill"
        } else {
            symbol = "speaker.wave.3.fill"
        }
        muteButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }
}
