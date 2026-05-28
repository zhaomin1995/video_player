import Cocoa

class PlaybackButtons: NSView {
    var onPlayPause: (() -> Void)?
    var onSeekBackward: (() -> Void)?
    var onSeekForward: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?

    private let prevButton = NSButton()
    private let seekBackButton = NSButton()
    private let playPauseButton = NSButton()
    private let seekForwardButton = NSButton()
    private let nextButton = NSButton()

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
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        configureButton(prevButton, symbol: "backward.end.fill", action: #selector(prevClicked))
        configureButton(seekBackButton, symbol: "gobackward.5", action: #selector(seekBackClicked))
        configureButton(playPauseButton, symbol: "play.fill", action: #selector(playPauseClicked))
        configureButton(seekForwardButton, symbol: "goforward.5", action: #selector(seekForwardClicked))
        configureButton(nextButton, symbol: "forward.end.fill", action: #selector(nextClicked))

        prevButton.setAccessibilityLabel(L("Previous"))
        seekBackButton.setAccessibilityLabel(L("Seek Backward"))
        playPauseButton.setAccessibilityLabel(L("Play / Pause"))
        seekForwardButton.setAccessibilityLabel(L("Seek Forward"))
        nextButton.setAccessibilityLabel(L("Next"))

        playPauseButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        playPauseButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        stack.addArrangedSubview(prevButton)
        stack.addArrangedSubview(seekBackButton)
        stack.addArrangedSubview(playPauseButton)
        stack.addArrangedSubview(seekForwardButton)
        stack.addArrangedSubview(nextButton)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func configureButton(_ button: NSButton, symbol: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.isBordered = false
        button.contentTintColor = .white
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.imageScaling = .scaleProportionallyUpOrDown
    }

    func setPlaying(_ playing: Bool) {
        let symbol = playing ? "pause.fill" : "play.fill"
        playPauseButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        // Keep the VoiceOver label in sync with the toggled state so blind
        // users hear the current action, not the original "Play / Pause".
        playPauseButton.setAccessibilityLabel(playing ? L("Pause") : L("Play"))
    }

    @objc private func prevClicked() { onPrevious?() }
    @objc private func seekBackClicked() { onSeekBackward?() }
    @objc private func playPauseClicked() { onPlayPause?() }
    @objc private func seekForwardClicked() { onSeekForward?() }
    @objc private func nextClicked() { onNext?() }
}
