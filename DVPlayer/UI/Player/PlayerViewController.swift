import Cocoa
import AVFoundation

class PlayerViewController: NSViewController {
    private let videoView = VideoView()
    private let controlBarView = ControlBarView()
    private let subtitleOverlayView = SubtitleOverlayView()
    private let osdView = OSDView()
    private var controlBarBottomConstraint: NSLayoutConstraint?

    var onMouseMoved: (() -> Void)?
    var onFileDropped: ((URL) -> Void)?
    var onDoubleClick: (() -> Void)?

    private var player: AVPlayer?
    private var playerEngine: AVPlayerEngine?
    private var timeObserver: Any?

    var isPaused: Bool {
        player?.rate == 0
    }

    override func loadView() {
        let dragDropView = DragDropView()
        dragDropView.wantsLayer = true
        dragDropView.layer?.backgroundColor = NSColor.black.cgColor
        dragDropView.onFileDropped = { [weak self] url in
            self?.onFileDropped?(url)
        }
        view = dragDropView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupVideoView()
        setupSubtitleOverlay()
        setupControlBar()
        setupOSD()
        setupGestureRecognizers()
        registerForDraggedTypes()
    }

    private func setupVideoView() {
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoView)
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupSubtitleOverlay() {
        subtitleOverlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleOverlayView)
        NSLayoutConstraint.activate([
            subtitleOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            subtitleOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            subtitleOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -60),
            subtitleOverlayView.heightAnchor.constraint(lessThanOrEqualToConstant: 120),
        ])
    }

    private func setupControlBar() {
        controlBarView.translatesAutoresizingMaskIntoConstraints = false
        controlBarView.delegate = self
        view.addSubview(controlBarView)

        let bottomConstraint = controlBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        controlBarBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            bottomConstraint,
            controlBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlBarView.heightAnchor.constraint(equalToConstant: 80),
        ])
    }

    private func setupOSD() {
        osdView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(osdView)
        NSLayoutConstraint.activate([
            osdView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            osdView.topAnchor.constraint(equalTo: view.topAnchor, constant: 50),
        ])
    }

    private func setupGestureRecognizers() {
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClick.numberOfClicksRequired = 2
        view.addGestureRecognizer(doubleClick)
    }

    private func registerForDraggedTypes() {
        // Drag and drop handled by DragDropView (the root view)
    }

    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        onDoubleClick?()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseMoved?()
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        if abs(delta) > 0.5 {
            let volumeDelta = Float(delta > 0 ? 0.05 : -0.05)
            adjustVolume(by: volumeDelta)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers else {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch (characters, modifiers) {
        case (" ", []):
            togglePlayPause()
        case ("f", []), ("f", .command):
            onDoubleClick?()
        case ("m", []):
            toggleMute()
        case (String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), []):
            seek(by: -5)
        case (String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), []):
            seek(by: 5)
        case (String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), .shift):
            seek(by: -30)
        case (String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), .shift):
            seek(by: 30)
        case (String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), .command):
            seek(by: -60)
        case (String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), .command):
            seek(by: 60)
        case (String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), []):
            adjustVolume(by: 0.05)
        case (String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)), []):
            adjustVolume(by: -0.05)
        case ("[", []):
            adjustSpeed(by: -0.25)
        case ("]", []):
            adjustSpeed(by: 0.25)
        case ("\\", []):
            setSpeed(1.0)
        default:
            super.keyDown(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Playback

    func openFile(url: URL) {
        playerEngine?.stop()

        let engine = AVPlayerEngine()
        playerEngine = engine
        engine.delegate = self

        if url.isNativeAVPlayerFormat {
            playWithEngine(engine, url: url)
        } else {
            osdView.show(message: "Remuxing \(url.pathExtension.uppercased())…", duration: 3.0)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var success = false
                do {
                    try FFmpegBridge.remuxFile(url.path, toOutput: tempURL.path)
                    success = true
                } catch {
                    print("Remux failed: \(error)")
                }
                DispatchQueue.main.async {
                    if success {
                        self?.playWithEngine(engine, url: tempURL)
                        self?.osdView.show(message: "Playing")
                    } else {
                        self?.playWithEngine(engine, url: url)
                    }
                }
            }
        }
    }

    private var playbackStatusObservation: NSKeyValueObservation?

    private func playWithEngine(_ engine: AVPlayerEngine, url: URL) {
        print("[DVPlayer] Opening: \(url.path)")
        engine.open(url: url)
        videoView.setPlayer(engine.player)

        playbackStatusObservation = engine.player?.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else {
                if item.status == .failed {
                    print("[DVPlayer] Player item FAILED: \(item.error?.localizedDescription ?? "?")")
                }
                return
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                print("[DVPlayer] Ready to play! Duration: \(engine.duration)s")
                self.controlBarView.setDuration(engine.duration)
                engine.play()
                self.controlBarView.setPlaying(true)

                if let window = self.view.window as? PlayerWindow, let videoSize = engine.videoSize {
                    window.setAspectRatio(videoSize)
                    let screenFrame = NSScreen.main?.visibleFrame ?? .zero
                    let scale = min(screenFrame.width * 0.7 / videoSize.width, screenFrame.height * 0.7 / videoSize.height, 1.0)
                    let newSize = NSSize(width: videoSize.width * scale, height: videoSize.height * scale)
                    window.setContentSize(newSize)
                    window.center()
                }
            }
        }
    }

    func togglePlayPause() {
        guard let engine = playerEngine else { return }
        if engine.isPlaying {
            engine.pause()
            osdView.show(message: "Paused")
        } else {
            engine.play()
            osdView.show(message: "Playing")
        }
        controlBarView.setPlaying(engine.isPlaying)
    }

    func seek(by seconds: Double) {
        playerEngine?.seek(by: seconds)
        osdView.show(message: "Seek \(seconds > 0 ? "+" : "")\(Int(seconds))s")
    }

    func adjustVolume(by delta: Float) {
        guard let engine = playerEngine else { return }
        let newVolume = max(0, min(1, engine.volume + delta))
        engine.volume = newVolume
        controlBarView.setVolume(newVolume)
        osdView.show(message: "Volume: \(Int(newVolume * 100))%")
    }

    func toggleMute() {
        guard let engine = playerEngine else { return }
        engine.isMuted.toggle()
        controlBarView.setMuted(engine.isMuted)
        osdView.show(message: engine.isMuted ? "Muted" : "Unmuted")
    }

    func adjustSpeed(by delta: Float) {
        guard let engine = playerEngine else { return }
        let newRate = max(0.25, min(4.0, engine.rate + delta))
        engine.rate = newRate
        controlBarView.setSpeed(newRate)
        osdView.show(message: String(format: "Speed: %.2fx", newRate))
    }

    func setSpeed(_ speed: Float) {
        playerEngine?.rate = speed
        controlBarView.setSpeed(speed)
        osdView.show(message: String(format: "Speed: %.2fx", speed))
    }

    func showControlBar(animated: Bool) {
        if animated {
            controlBarView.animator().alphaValue = 1.0
        } else {
            controlBarView.alphaValue = 1.0
        }
    }

    func hideControlBar(animated: Bool) {
        if animated {
            controlBarView.animator().alphaValue = 0.0
        } else {
            controlBarView.alphaValue = 0.0
        }
    }
}

// MARK: - ControlBarDelegate

extension PlayerViewController: ControlBarDelegate {
    func controlBarPlayPauseClicked() {
        togglePlayPause()
    }

    func controlBarSeekRequested(to fraction: Double) {
        playerEngine?.seekToFraction(fraction)
    }

    func controlBarVolumeChanged(to volume: Float) {
        playerEngine?.volume = volume
        osdView.show(message: "Volume: \(Int(volume * 100))%")
    }

    func controlBarSpeedChanged(to speed: Float) {
        setSpeed(speed)
    }

    func controlBarSeekBackward() {
        seek(by: -5)
    }

    func controlBarSeekForward() {
        seek(by: 5)
    }
}

// MARK: - AVPlayerEngineDelegate

extension PlayerViewController: AVPlayerEngineDelegate {
    func playerEngineTimeDidChange(current: Double, duration: Double) {
        controlBarView.updateTime(current: current, duration: duration)
    }

    func playerEngineDidFinishPlaying() {
        controlBarView.setPlaying(false)
    }

    func playerEngineDidUpdateStatus(isPlaying: Bool) {
        controlBarView.setPlaying(isPlaying)
    }
}

// MARK: - Drag and Drop View

class DragDropView: NSView {
    var onFileDropped: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else {
            return []
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let url = urls.first else {
            return false
        }
        onFileDropped?(url)
        return true
    }
}
