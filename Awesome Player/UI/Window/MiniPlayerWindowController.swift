import Cocoa
import AVFoundation

/// Compact 380×120 always-on-top floating player that mirrors play state from
/// the active engine. Used as "music mode" — when toggled, the main window
/// hides; the engine keeps playing because both engines outlive the window
/// they were created from. Toggling back restores the main window.
///
/// Why no embedded video: moving libvlc's `renderView` between window
/// hierarchies mid-playback is fragile (the layer is bound to a parent
/// NSWindow at libvlc_media_player_set_nsobject time). Audio + metadata is
/// the canonical music-mode UX and avoids that whole class of bug. Users who
/// want a floating video should use PiP, which already works.
///
/// Mirrors state via a 0.5s polling timer on the active engine — same cadence
/// as the main control bar's time updates. Cheap, no observer wiring.
final class MiniPlayerWindowController: NSWindowController {

    private weak var playerVC: PlayerViewController?

    private let titleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "0:00 / 0:00")
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1,
                                  target: nil, action: nil)
    private let playButton = NSButton(title: "", target: nil, action: nil)
    private let prevButton = NSButton(title: "", target: nil, action: nil)
    private let nextButton = NSButton(title: "", target: nil, action: nil)
    private let restoreButton = NSButton(title: "", target: nil, action: nil)

    private var pollTimer: Timer?

    init(playerVC: PlayerViewController) {
        self.playerVC = playerVC

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered, defer: true)
        panel.title = L("Music Mode")
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.center()

        super.init(window: panel)
        panel.delegate = self
        setupContent()
        startPolling()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit { stopPolling() }

    private func setupContent() {
        guard let content = window?.contentView else { return }

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.controlSize = .small
        slider.translatesAutoresizingMaskIntoConstraints = false

        let symConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let bigConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)

        prevButton.image = NSImage(systemSymbolName: "backward.fill", accessibilityDescription: L("Previous"))?
            .withSymbolConfiguration(symConfig)
        prevButton.target = self
        prevButton.action = #selector(prev)
        prevButton.isBordered = false
        prevButton.translatesAutoresizingMaskIntoConstraints = false

        playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: L("Play"))?
            .withSymbolConfiguration(bigConfig)
        playButton.target = self
        playButton.action = #selector(togglePlay)
        playButton.isBordered = false
        playButton.translatesAutoresizingMaskIntoConstraints = false

        nextButton.image = NSImage(systemSymbolName: "forward.fill", accessibilityDescription: L("Next"))?
            .withSymbolConfiguration(symConfig)
        nextButton.target = self
        nextButton.action = #selector(next)
        nextButton.isBordered = false
        nextButton.translatesAutoresizingMaskIntoConstraints = false

        restoreButton.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right",
                                       accessibilityDescription: L("Restore Full Player"))?
            .withSymbolConfiguration(symConfig)
        restoreButton.target = self
        restoreButton.action = #selector(restoreFullPlayer)
        restoreButton.isBordered = false
        restoreButton.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, timeLabel, slider, prevButton, playButton, nextButton, restoreButton]
            .forEach { content.addSubview($0) }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            slider.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            slider.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            timeLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 2),
            timeLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            playButton.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            playButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            playButton.widthAnchor.constraint(equalToConstant: 36),
            playButton.heightAnchor.constraint(equalToConstant: 36),

            prevButton.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -16),
            prevButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 28),
            prevButton.heightAnchor.constraint(equalToConstant: 28),

            nextButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 16),
            nextButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 28),
            nextButton.heightAnchor.constraint(equalToConstant: 28),

            restoreButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            restoreButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            restoreButton.widthAnchor.constraint(equalToConstant: 24),
            restoreButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        refreshFromEngine()
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshFromEngine()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refreshFromEngine() {
        guard let vc = playerVC else { return }
        let current = vc.playerEngine?.currentTime ?? vc.vlcEngine?.currentTime ?? 0
        let duration = vc.playerEngine?.duration ?? vc.vlcEngine?.duration ?? 0
        let title = vc.currentFileURL?.deletingPathExtension().lastPathComponent
            ?? L("Nothing playing")
        let isPlaying = (vc.playerEngine?.isPlaying ?? false) || (vc.vlcEngine?.isPlaying ?? false)

        titleLabel.stringValue = title
        timeLabel.stringValue = "\(formatTime(current)) / \(formatTime(duration))"
        if duration > 0 {
            slider.maxValue = duration
            slider.doubleValue = current
        }
        let symbolName = isPlaying ? "pause.fill" : "play.fill"
        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        playButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: - Actions

    @objc private func togglePlay() { playerVC?.togglePlayPause() }
    @objc private func prev() { playerVC?.playPreviousTrack() }
    @objc private func next() { playerVC?.playNextTrack() }
    @objc private func restoreFullPlayer() {
        (NSApp.delegate as? AppDelegate)?.toggleMiniPlayer(nil)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        playerVC?.seekToAbsoluteTime(sender.doubleValue)
    }
}

extension MiniPlayerWindowController: NSWindowDelegate {
    /// Treat closing the mini panel the same as the restore button — restore
    /// the main window so the user isn't left with nothing visible while the
    /// engine continues to play in the background.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        (NSApp.delegate as? AppDelegate)?.toggleMiniPlayer(nil)
        return false   // toggleMiniPlayer handles the orderOut
    }
}
