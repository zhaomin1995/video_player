import Cocoa
import AVFoundation

protocol ControlBarDelegate: AnyObject {
    func controlBarPlayPauseClicked()
    func controlBarSeekRequested(to fraction: Double)
    func controlBarVolumeChanged(to volume: Float)
    func controlBarSpeedChanged(to speed: Float)
    func controlBarSeekBackward()
    func controlBarSeekForward()
}

class ControlBarView: NSView {
    weak var delegate: ControlBarDelegate?

    private let gradientView = GradientScrimView()
    private let effectView = NSView()
    private let seekSlider = SeekSliderView()
    private let playbackButtons = PlaybackButtons()
    private let currentTimeLabel = NSTextField(labelWithString: "0:00")
    private let durationLabel = NSTextField(labelWithString: "0:00")
    private let volumeSlider = VolumeSliderView()
    private let speedButton = SpeedButton()
    private let fullscreenButton = NSButton()
    private let airplayPlaceholder = NSView()

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

        // Dark gradient scrim behind controls for readability
        gradientView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gradientView)

        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
        effectView.layer?.masksToBounds = true
        effectView.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.95).cgColor
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        seekSlider.translatesAutoresizingMaskIntoConstraints = false
        seekSlider.onSeek = { [weak self] fraction in
            self?.delegate?.controlBarSeekRequested(to: fraction)
        }
        effectView.addSubview(seekSlider)

        playbackButtons.translatesAutoresizingMaskIntoConstraints = false
        playbackButtons.onPlayPause = { [weak self] in
            self?.delegate?.controlBarPlayPauseClicked()
        }
        playbackButtons.onSeekBackward = { [weak self] in
            self?.delegate?.controlBarSeekBackward()
        }
        playbackButtons.onSeekForward = { [weak self] in
            self?.delegate?.controlBarSeekForward()
        }
        effectView.addSubview(playbackButtons)

        configureTimeLabel(currentTimeLabel)
        configureTimeLabel(durationLabel)
        effectView.addSubview(currentTimeLabel)
        effectView.addSubview(durationLabel)

        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.onVolumeChanged = { [weak self] volume in
            self?.delegate?.controlBarVolumeChanged(to: volume)
        }
        effectView.addSubview(volumeSlider)

        speedButton.translatesAutoresizingMaskIntoConstraints = false
        speedButton.onSpeedChanged = { [weak self] speed in
            self?.delegate?.controlBarSpeedChanged(to: speed)
        }
        effectView.addSubview(speedButton)

        fullscreenButton.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Fullscreen")
        fullscreenButton.isBordered = false
        fullscreenButton.contentTintColor = .white
        fullscreenButton.target = self
        fullscreenButton.action = #selector(fullscreenClicked)
        fullscreenButton.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(fullscreenButton)

        setupConstraints()
    }

    private func configureTimeLabel(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Gradient scrim extends above the control bar for smooth fade
            gradientView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: bottomAnchor),
            gradientView.heightAnchor.constraint(equalToConstant: 140),

            effectView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            seekSlider.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 8),
            seekSlider.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 12),
            seekSlider.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -12),
            seekSlider.heightAnchor.constraint(equalToConstant: 20),

            playbackButtons.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 12),
            playbackButtons.topAnchor.constraint(equalTo: seekSlider.bottomAnchor, constant: 6),
            playbackButtons.heightAnchor.constraint(equalToConstant: 28),

            currentTimeLabel.leadingAnchor.constraint(equalTo: playbackButtons.trailingAnchor, constant: 10),
            currentTimeLabel.centerYAnchor.constraint(equalTo: playbackButtons.centerYAnchor),

            durationLabel.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 4),
            durationLabel.centerYAnchor.constraint(equalTo: playbackButtons.centerYAnchor),

            volumeSlider.leadingAnchor.constraint(equalTo: durationLabel.trailingAnchor, constant: 14),
            volumeSlider.centerYAnchor.constraint(equalTo: playbackButtons.centerYAnchor),
            volumeSlider.widthAnchor.constraint(equalToConstant: 100),
            volumeSlider.heightAnchor.constraint(equalToConstant: 20),

            speedButton.leadingAnchor.constraint(equalTo: volumeSlider.trailingAnchor, constant: 10),
            speedButton.centerYAnchor.constraint(equalTo: playbackButtons.centerYAnchor),

            fullscreenButton.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -12),
            fullscreenButton.centerYAnchor.constraint(equalTo: playbackButtons.centerYAnchor),
            fullscreenButton.widthAnchor.constraint(equalToConstant: 24),
            fullscreenButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @objc private func fullscreenClicked() {
        window?.toggleFullScreen(nil)
    }

    // MARK: - Public API

    func setPlaying(_ playing: Bool) {
        playbackButtons.setPlaying(playing)
    }

    func updateTime(current: Double, duration: Double) {
        currentTimeLabel.stringValue = formatTime(current)
        durationLabel.stringValue = " / \(formatTime(duration))"
        if duration > 0 {
            seekSlider.setProgress(current / duration)
        }
    }

    func setDuration(_ duration: Double) {
        durationLabel.stringValue = " / \(formatTime(duration))"
    }

    func setVolume(_ volume: Float) {
        volumeSlider.setVolume(volume)
    }

    func setMuted(_ muted: Bool) {
        volumeSlider.setMuted(muted)
    }

    func setSpeed(_ speed: Float) {
        speedButton.setSpeed(speed)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
