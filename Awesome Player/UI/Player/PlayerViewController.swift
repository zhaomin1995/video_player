/// Main playback view controller. Handles two code paths for opening files:
/// - Native formats (MP4/MOV with H.264/HEVC) go directly to AVPlayer
/// - Non-native formats (MKV, AVI, etc.) are remuxed to a temp MP4 via FFmpeg first
///
/// The remux path keeps all playback through AVPlayer, which preserves Dolby Vision
/// and AirPlay support. A direct FFmpeg software decoder engine is planned but not yet wired up.
import Cocoa
import AVFoundation
import AVKit

class PlayerViewController: NSViewController {
    private let videoView = VideoView()
    private let welcomeView = WelcomeView()
    private let controlBarView = ControlBarView()
    private let subtitleOverlayView = SubtitleOverlayView()
    private let osdView = OSDView()
    private var controlBarBottomConstraint: NSLayoutConstraint?
    private var subtitleBottomConstraint: NSLayoutConstraint?

    var onMouseMoved: (() -> Void)?
    var onFileDropped: ((URL) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?

    private(set) var playerEngine: AVPlayerEngine?
    private(set) var vlcEngine: VLCPlayerEngine?

    private let subtitleManager = SubtitleManager()
    private let playlistManager = PlaylistManager()
    private let abLoopController = ABLoopController()
    private(set) var currentFileURL: URL?
    /// The URL the engine is actually decoding. Equals currentFileURL for the
    /// straight AVPlayer / VLC paths, but for Dolby Vision content it points
    /// at the remuxed-to-MP4 temp file. Cast/AirPlay paths must use THIS so
    /// receivers get the format AVKit/Chromecast can actually consume.
    var playbackSourceURL: URL?
    /// Tracks the current DV remux output so we can delete it on the next
    /// openFile or on app terminate. Without this, temp .mp4 files leak.
    private var dvRemuxOutputURL: URL?
    private var videoRotation: CGFloat = 0
    private var videoFlippedH = false
    private var videoFlippedV = false
    private var isFillScreen = false
    private var pipController: AVPictureInPictureController?
    private var playlistPanel: PlaylistPanelView?
    private var playlistPanelConstraint: NSLayoutConstraint?
    private var audioDelayOffset: Double = 0
    private let passthroughManager = AudioPassthroughManager()
    private var hasResizedForCurrentFile = false
    private var currentFileIsDolbyVision = false
    private(set) var chapters: [[String: Any]] = []

    var isPaused: Bool {
        if let vlc = vlcEngine { return !vlc.isPlaying }
        return (playerEngine?.player?.rate ?? 0) == 0
    }

    private func resizeWindowToFitVideo(_ videoSize: NSSize) {
        guard let window = view.window, let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }

        // Apply Smart Zoom: upscale floor for small videos. The preference is a
        // percentage (100 = no upscale, 150-400 = upscale floor). Example: a 480p
        // video with smartZoom=200 displays at 960p minimum.
        let smartZoom = max(100, UserDefaults.standard.integer(forKey: Defaults.smartZoomPercent))
        let effectiveSize = NSSize(
            width: videoSize.width * CGFloat(smartZoom) / 100,
            height: videoSize.height * CGFloat(smartZoom) / 100
        )

        // User default width: if set (>0), force the window to that width and
        // compute the matching aspect-preserved height. Otherwise fit-to-screen
        // at 70% of the smaller dimension.
        let userWidth = UserDefaults.standard.integer(forKey: Defaults.userDefaultWidth)
        let newSize: NSSize
        if userWidth > 0 {
            let aspect = effectiveSize.height / effectiveSize.width
            let w = min(CGFloat(userWidth), screenFrame.width)
            newSize = NSSize(width: w, height: w * aspect)
        } else {
            let scale = min(screenFrame.width * 0.7 / effectiveSize.width,
                            screenFrame.height * 0.7 / effectiveSize.height,
                            2.0)
            newSize = NSSize(width: max(640, effectiveSize.width * scale),
                             height: max(360, effectiveSize.height * scale))
        }
        window.setContentSize(newSize)
        window.center()
    }

    // MARK: - Preference Readers
    //
    // These are read on every hot-path event (key down, scroll, seek). Cached
    // as stored properties + refreshed on UserDefaults.didChangeNotification
    // rather than re-reading from UserDefaults each time. Keeps event handlers
    // cheap and avoids reading stale-during-mutation values inside a single
    // event sequence.

    private var shortSeek: Double = 5
    private var longSeek: Double = 30
    private var useKeyframeSeeking: Bool = false
    private var scrollAction: Int = 0
    private var defaultsObserver: NSObjectProtocol?

    private func refreshCachedPreferences() {
        let ud = UserDefaults.standard
        let s = ud.double(forKey: Defaults.shortSeekInterval)
        shortSeek = s >= 1 ? s : 5
        let l = ud.double(forKey: Defaults.longSeekInterval)
        longSeek = l >= 1 ? l : 30
        useKeyframeSeeking = ud.bool(forKey: Defaults.keyFrameSeeking)
        scrollAction = ud.integer(forKey: Defaults.scrollWheelAction)
    }

    private func observePreferenceChanges() {
        refreshCachedPreferences()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshCachedPreferences()
        }
    }

    override func loadView() {
        let dragDropView = DragDropView()
        dragDropView.wantsLayer = true
        dragDropView.layer?.backgroundColor = NSColor.black.cgColor
        dragDropView.onFileDropped = { [weak self] url in
            self?.onFileDropped?(url)
        }
        dragDropView.onArrowKey = { [weak self] key in
            guard let self = self else { return }
            switch UInt(key) {
            case UInt(NSLeftArrowFunctionKey):  self.seek(by: -self.shortSeek)
            case UInt(NSRightArrowFunctionKey): self.seek(by: self.shortSeek)
            case UInt(NSUpArrowFunctionKey):    self.adjustVolume(by: 0.05)
            case UInt(NSDownArrowFunctionKey):  self.adjustVolume(by: -0.05)
            default: break
            }
        }
        view = dragDropView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupVideoView()
        setupWelcomeView()
        setupSubtitleOverlay()
        setupControlBar()
        setupOSD()
        setupGestureRecognizers()
        abLoopController.delegate = self
        passthroughManager.delegate = self
        Self.purgeOrphanedDVRemuxFiles()
        observePreferenceChanges()
    }

    deinit {
        if let observer = defaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Wipe any leftover DV remux outputs from a previous run. The naming
    /// convention (UUID + "_full.mp4") makes them easy to recognize without
    /// risking unrelated temp files.
    private static func purgeOrphanedDVRemuxFiles() {
        let tmp = FileManager.default.temporaryDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }
        for url in entries where url.lastPathComponent.hasSuffix("_full.mp4") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(view)

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(trackingArea)
    }

    private func setupVideoView() {
        videoView.onFileDropped = { [weak self] url in
            self?.onFileDropped?(url)
        }
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoView)
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupWelcomeView() {
        welcomeView.onFileDropped = { [weak self] url in
            self?.onFileDropped?(url)
        }
        welcomeView.onRecentClicked = { [weak self] url in
            self?.openFile(url: url)
        }
        welcomeView.onOpenFileClicked = {
            (NSApp.delegate as? AppDelegate)?.openFileAction(nil)
        }
        welcomeView.onOpenURLClicked = {
            (NSApp.delegate as? AppDelegate)?.openURL(nil)
        }
        welcomeView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(welcomeView)
        NSLayoutConstraint.activate([
            welcomeView.topAnchor.constraint(equalTo: view.topAnchor),
            welcomeView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            welcomeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            welcomeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupSubtitleOverlay() {
        subtitleOverlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleOverlayView)
        let bottomOffset = subtitleBottomOffset()
        let bottom = subtitleOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: bottomOffset)
        subtitleBottomConstraint = bottom
        NSLayoutConstraint.activate([
            subtitleOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            subtitleOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            bottom,
            subtitleOverlayView.heightAnchor.constraint(lessThanOrEqualToConstant: 120),
        ])
    }

    private func subtitleBottomOffset() -> CGFloat {
        let pos = UserDefaults.standard.integer(forKey: Defaults.subtitlePosition)
        switch pos {
        case 1: return -20   // Bottom of screen
        case 2: return -10   // Letterbox
        default: return -60  // Bottom of video (with padding)
        }
    }

    func updateSubtitlePosition() {
        subtitleBottomConstraint?.constant = subtitleBottomOffset()
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

        let pinch = NSMagnificationGestureRecognizer(target: self, action: #selector(handlePinch))
        view.addGestureRecognizer(pinch)
    }

    @objc private func handlePinch(_ gesture: NSMagnificationGestureRecognizer) {
        let action = UserDefaults.standard.integer(forKey: Defaults.pinchGestureAction)
        guard action != 2, gesture.state == .ended else { return } // 2 = nothing
        if gesture.magnification > 0.3 {
            if !(view.window?.styleMask.contains(.fullScreen) ?? false) {
                onDoubleClick?() // Enter fullscreen
            }
        } else if gesture.magnification < -0.3 {
            if view.window?.styleMask.contains(.fullScreen) ?? false {
                onDoubleClick?() // Exit fullscreen
            }
        }
    }

    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        onDoubleClick?()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseMoved?()
    }

    /// Scroll-wheel adjusts volume in fixed steps (not proportional to delta)
    /// to avoid accidental large jumps from trackpad momentum scrolling.
    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.5 else { return }
        switch scrollAction {
        case 0: adjustVolume(by: Float(delta > 0 ? 0.05 : -0.05))
        case 1: seek(by: delta > 0 ? shortSeek : -shortSeek)
        default: break
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let action = KeyBindingManager.shared.action(for: event) {
            handlePlayerAction(action)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let action = KeyBindingManager.shared.action(for: event) {
            handlePlayerAction(action)
            return
        }

        guard let characters = event.charactersIgnoringModifiers else {
            super.keyDown(with: event)
            return
        }

        // Escape handling (not rebindable)
        if characters == String(Character(UnicodeScalar(27))) {
            let behavior = UserDefaults.standard.integer(forKey: Defaults.escapeKeyBehavior)
            switch behavior {
            case 0:
                if view.window?.styleMask.contains(.fullScreen) ?? false { onDoubleClick?() }
            case 1:
                if playlistPanel?.isHidden == false { togglePlaylistPanel() }
            case 2:
                playerEngine?.stop(); vlcEngine?.stop()
                welcomeView.isHidden = false; controlBarView.setVideoActive(false)
                welcomeView.refreshRecents()
            default: break
            }
            return
        }

        super.keyDown(with: event)
    }

    private func handlePlayerAction(_ action: PlayerAction) {
        switch action {
        case .playPause: togglePlayPause()
        case .seekForwardShort: seek(by: shortSeek)
        case .seekBackwardShort: seek(by: -shortSeek)
        case .seekForwardLong: seek(by: longSeek)
        case .seekBackwardLong: seek(by: -longSeek)
        case .seekForwardExtraLong: seek(by: longSeek * 2)
        case .seekBackwardExtraLong: seek(by: -longSeek * 2)
        case .volumeUp: adjustVolume(by: 0.05)
        case .volumeDown: adjustVolume(by: -0.05)
        case .mute: toggleMute()
        case .fullscreen: onDoubleClick?()
        case .speedUp: adjustSpeed(by: 0.25)
        case .speedDown: adjustSpeed(by: -0.25)
        case .speedReset: setSpeed(1.0)
        case .frameForward: stepFrame(forward: true)
        case .frameBackward: stepFrame(forward: false)
        case .nextChapter: seekToNextChapter()
        case .previousChapter: seekToPreviousChapter()
        }
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Context Menu

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        menu.addItem(withTitle: (playerEngine?.isPlaying ?? vlcEngine?.isPlaying ?? false) ? L("Pause") : L("Play"),
            action: #selector(AppDelegate.togglePlayPause(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(withTitle: L("Seek Forward 5s"), action: #selector(AppDelegate.seekForward5(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Seek Backward 5s"), action: #selector(AppDelegate.seekBackward5(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        let audioTrack = NSMenuItem(title: L("Audio Track"), action: nil, keyEquivalent: "")
        let audioSubmenu = NSMenu(title: L("Audio Track"))
        audioSubmenu.delegate = TrackMenuDelegate.audio
        audioTrack.submenu = audioSubmenu
        menu.addItem(audioTrack)

        let subTrack = NSMenuItem(title: L("Subtitle Track"), action: nil, keyEquivalent: "")
        let subSubmenu = NSMenu(title: L("Subtitle Track"))
        subSubmenu.delegate = TrackMenuDelegate.subtitle
        subTrack.submenu = subSubmenu
        menu.addItem(subTrack)

        menu.addItem(.separator())

        let speedItem = NSMenuItem(title: L("Speed"), action: nil, keyEquivalent: "")
        let speedSubmenu = NSMenu(title: L("Speed"))
        for speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
            speedSubmenu.addItem(withTitle: String(format: "%.2gx", speed),
                                action: #selector(AppDelegate.setSpeed(_:)), keyEquivalent: "")
        }
        speedItem.submenu = speedSubmenu
        menu.addItem(speedItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: L("Screenshot"), action: #selector(AppDelegate.saveScreenshot(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Enter Full Screen"), action: #selector(AppDelegate.toggleFullScreenAction(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Picture in Picture"), action: #selector(AppDelegate.togglePiP(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Keep on Top"), action: #selector(AppDelegate.toggleAlwaysOnTop(_:)), keyEquivalent: "")

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    // MARK: - Playback

    func saveCurrentPosition() {
        guard let url = currentFileURL else { return }
        let current = playerEngine?.currentTime ?? vlcEngine?.currentTime ?? 0
        let dur = playerEngine?.duration ?? vlcEngine?.duration ?? 0
        ResumeManager.savePosition(current, duration: dur, for: url)
    }

    func openFile(url: URL) {
        saveCurrentPosition()
        // Drop any in-flight engine observation BEFORE clobbering state so
        // its closure can't fire against the new engine that's about to
        // replace it (race window between assignment and the next .new tick).
        playbackStatusObservation = nil
        // Delete the prior DV remux temp file (if any) — each session can
        // open many DV files; without this they accumulate in /var/folders.
        if let prior = dvRemuxOutputURL {
            try? FileManager.default.removeItem(at: prior)
            dvRemuxOutputURL = nil
        }
        currentFileURL = url
        playbackSourceURL = url
        hasResizedForCurrentFile = false

        // Reset per-file state
        subtitleManager.clear()
        subtitleOverlayView.setText(nil)
        audioDelayOffset = 0
        abLoopController.clear()
        videoRotation = 0
        videoFlippedH = false
        videoFlippedV = false
        isFillScreen = false
        videoView.setLayerTransform(CATransform3DIdentity)
        chapters = []
        currentFileIsDolbyVision = false
        playbackStatusObservation = nil
        welcomeView.isHidden = true
        controlBarView.setVideoActive(true)
        playerEngine?.stop()

        if !playlistManager.items.contains(url) {
            playlistManager.addItem(url)
        }
        _ = playlistManager.selectItem(at: playlistManager.items.firstIndex(of: url) ?? 0)

        abLoopController.gap = UserDefaults.standard.double(forKey: Defaults.abLoopGap)

        vlcEngine?.stop()
        vlcEngine = nil

        if url.isNativeAVPlayerFormat {
            // Native MP4/MOV — use AVPlayer for Dolby Vision + AirPlay
            startAVPlayerEngine(url: url)
        } else {
            // Non-native (MKV, AVI, etc.): probe for Dolby Vision in the
            // background so the main thread isn't blocked. avformat_find_stream_info
            // can take 100-300ms on 4K files because it reads packets to detect
            // codecs; doing it sync caused a visible UI hitch on every file open.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let isDV = FFmpegBridge.probeFile(url.path).hasDolbyVision.boolValue
                DispatchQueue.main.async {
                    // Bail out if the user opened a different file mid-probe
                    guard let self = self, self.currentFileURL == url else { return }
                    if isDV {
                        self.startDolbyVisionRemuxFlow(url: url)
                    } else {
                        self.startVLCEngine(url: url)
                    }
                }
            }
        }

        // Resume playback from saved position
        if UserDefaults.standard.bool(forKey: Defaults.resumePlayback),
           let savedPos = ResumeManager.savedPosition(for: url), savedPos > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.playerEngine?.seekTo(time: savedPos)
                self?.vlcEngine?.seekTo(time: savedPos)
                self?.osdView.show(message: String(format: L("Resumed from %@"), self?.formatSeekTime(savedPos) ?? "0:00"))
            }
        }

        // Update Now Playing
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.nowPlayingController.updateNowPlaying(
                title: url.deletingPathExtension().lastPathComponent,
                duration: playerEngine?.duration ?? vlcEngine?.duration ?? 0
            )
        }

        // Auto-load matching external subtitle files. Embedded subtitle
        // extraction (for AVPlayer-based paths) is deferred to the engine
        // helpers because the engine choice is resolved asynchronously for
        // non-native files — checking `vlcEngine == nil` here would race.
        if UserDefaults.standard.bool(forKey: Defaults.autoLoadSubtitles) {
            let subs = SubtitleManager.findSubtitleFiles(for: url)
            if let first = subs.first {
                subtitleManager.loadSubtitle(from: first)
            }
        }

        // Load chapters
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let chs = FFmpegBridge.chapters(forFile: url.path) as? [[String: Any]] ?? []
            DispatchQueue.main.async {
                self?.chapters = chs
            }
        }

        // Set up seek bar thumbnails
        if url.isNativeAVPlayerFormat {
            let asset = AVURLAsset(url: url)
            controlBarView.setSeekBarAsset(asset)
        } else {
            controlBarView.setSeekBarAsset(nil)
        }

        // Evaluate passthrough and update title bar badges
        let isNative = url.isNativeAVPlayerFormat
        Task {
            let info = await MediaInfo.probe(url: url)
            await MainActor.run {
                self.passthroughManager.evaluateForMedia(audioCodec: info.audioCodecName)

                var codecName = info.videoCodec.rawValue
                var isDV = info.isDolbyVision
                var isHDR = info.hdrType != .sdr
                let isAtmos = info.isDolbyAtmos

                if !isNative || codecName == VideoCodec.unknown.rawValue {
                    if let ffName = FFmpegBridge.videoCodecName(forFile: url.path) {
                        codecName = ffName
                    }
                    let probe = FFmpegBridge.probeFile(url.path)
                    if probe.hasDolbyVision.boolValue { isDV = true; isHDR = true }
                    if probe.hasHDR.boolValue { isHDR = true }
                }

                self.currentFileIsDolbyVision = isDV

                // DV needs to intercept the AirPlay button so we can route
                // through our transcode-and-libvlc-renderer flow instead of
                // AVKit's picker (which silently fails against Samsung TVs).
                // Marking the cast button as "needs overlay" routes clicks
                // through controlBarAirPlayRequested() where we branch on DV.
                if isDV {
                    self.controlBarView.setAirPlayAvailable(false)
                }

                if let wc = self.view.window?.windowController as? PlayerWindowController {
                    wc.titleBarView.updateBadges(
                        isDolbyVision: isDV,
                        isHDR: isHDR,
                        codecName: codecName,
                        isAtmos: isAtmos
                    )
                }
            }
        }
    }

    // MARK: - Engine Selection (called from openFile)

    private func startAVPlayerEngine(url: URL) {
        let engine = AVPlayerEngine()
        playerEngine = engine
        engine.delegate = self
        engine.useKeyframeSeeking = useKeyframeSeeking
        let vol = UserDefaults.standard.double(forKey: Defaults.defaultVolume)
        engine.volume = Float(vol > 0 ? vol : 1.0)
        controlBarView.setVolume(engine.volume)
        let speed = UserDefaults.standard.double(forKey: Defaults.defaultSpeed)
        if speed > 0 && speed != 1.0 {
            engine.rate = Float(speed)
            controlBarView.setSpeed(Float(speed))
        }
        playWithEngine(engine, url: url, fallbackRemux: false)
        controlBarView.setAirPlayAvailable(true)
        loadEmbeddedSubtitlesIfNeeded(url: url)
    }

    /// Dolby Vision in a non-native container (e.g. MKV). libvlc renders
    /// DV Profile 5 with wrong colors (IPT-PQ pixels misinterpreted as
    /// BT.2020). Remux to MP4 so AVPlayer's hardware DV decoder handles it.
    private func startDolbyVisionRemuxFlow(url: URL) {
        let engine = AVPlayerEngine()
        playerEngine = engine
        engine.delegate = self
        engine.useKeyframeSeeking = useKeyframeSeeking
        // AVKit's AirPlay handshake fails against Samsung's third-party
        // AirPlay 2 receiver for DV content (session opens, no media flows).
        // Disable external playback to prevent AVKit from auto-engaging.
        engine.allowsExternalPlayback = false
        let vol = UserDefaults.standard.double(forKey: Defaults.defaultVolume)
        engine.volume = Float(vol > 0 ? vol : 1.0)
        controlBarView.setVolume(engine.volume)
        let speed = UserDefaults.standard.double(forKey: Defaults.defaultSpeed)
        if speed > 0 && speed != 1.0 {
            engine.rate = Float(speed)
            controlBarView.setSpeed(Float(speed))
        }
        controlBarView.setAirPlayAvailable(true)
        osdView.show(message: L("Preparing Dolby Vision playback…"), duration: 60.0)
        remuxAndPlay(engine: engine, url: url)
        loadEmbeddedSubtitlesIfNeeded(url: url)
    }

    private func startVLCEngine(url: URL) {
        let engine = VLCPlayerEngine()
        vlcEngine = engine
        engine.delegate = self

        guard engine.open(url: url) else {
            osdView.show(message: L("Failed to open file"))
            return
        }

        // Embed VLC's render view into our video view
        let vlcView = engine.renderView
        vlcView.translatesAutoresizingMaskIntoConstraints = false
        videoView.subviews.forEach { $0.removeFromSuperview() }
        videoView.addSubview(vlcView)
        NSLayoutConstraint.activate([
            vlcView.topAnchor.constraint(equalTo: videoView.topAnchor),
            vlcView.bottomAnchor.constraint(equalTo: videoView.bottomAnchor),
            vlcView.leadingAnchor.constraint(equalTo: videoView.leadingAnchor),
            vlcView.trailingAnchor.constraint(equalTo: videoView.trailingAnchor),
        ])

        controlBarView.setAirPlayAvailable(false)
        controlBarView.setDuration(engine.duration)
        let vol = UserDefaults.standard.double(forKey: Defaults.defaultVolume)
        engine.volume = Float(vol > 0 ? vol : 1.0)
        controlBarView.setVolume(engine.volume)
        let speed = UserDefaults.standard.double(forKey: Defaults.defaultSpeed)
        if speed > 0 && speed != 1.0 {
            engine.rate = Float(speed)
            controlBarView.setSpeed(Float(speed))
        }

        let eqPreset = UserDefaults.standard.integer(forKey: Defaults.defaultEQPreset)
        if eqPreset > 0 { engine.setEqualizer(presetIndex: eqPreset) }

        engine.startRendererDiscovery()

        let autoPlay = UserDefaults.standard.bool(forKey: Defaults.autoPlayOnOpen)
        if autoPlay {
            engine.play()
            controlBarView.setPlaying(true)
        }
    }

    /// For AVPlayer-based paths only — VLC handles embedded subtitles natively.
    /// Skips if an external subtitle file was already loaded in openFile.
    private func loadEmbeddedSubtitlesIfNeeded(url: URL) {
        guard UserDefaults.standard.bool(forKey: Defaults.autoLoadSubtitles),
              !subtitleManager.hasSubtitles else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let tracks = FFmpegBridge.subtitleTracks(forFile: url.path)
            guard let firstTrack = tracks.first,
                  let index = firstTrack["index"] as? Int else { return }
            if let srtText = try? FFmpegBridge.extractSubtitleTrack(Int32(index), fromFile: url.path) {
                DispatchQueue.main.async {
                    self?.subtitleManager.loadSubtitleFromSRTText(srtText)
                    self?.osdView.show(message: L("Embedded subtitles loaded"))
                }
            }
        }
    }

    func openStream(videoURL: URL, audioURL: URL?) {
        saveCurrentPosition()
        welcomeView.isHidden = true
        controlBarView.setVideoActive(true)
        playerEngine?.stop()
        playerEngine = nil

        let engine = VLCPlayerEngine()
        vlcEngine?.stop()
        vlcEngine = engine
        engine.delegate = self

        if engine.open(url: videoURL, audioURL: audioURL) {
            let vlcView = engine.renderView
            vlcView.translatesAutoresizingMaskIntoConstraints = false
            videoView.subviews.forEach { $0.removeFromSuperview() }
            videoView.addSubview(vlcView)
            NSLayoutConstraint.activate([
                vlcView.topAnchor.constraint(equalTo: videoView.topAnchor),
                vlcView.bottomAnchor.constraint(equalTo: videoView.bottomAnchor),
                vlcView.leadingAnchor.constraint(equalTo: videoView.leadingAnchor),
                vlcView.trailingAnchor.constraint(equalTo: videoView.trailingAnchor),
            ])
            controlBarView.setAirPlayAvailable(false)
            let vol = UserDefaults.standard.double(forKey: Defaults.defaultVolume)
            engine.volume = Float(vol > 0 ? vol : 1.0)
            controlBarView.setVolume(engine.volume)
            engine.play()
            controlBarView.setPlaying(true)
        } else {
            showOSD(L("Failed to open stream"))
        }
    }

    private var playbackStatusObservation: NSKeyValueObservation?

    /// Wires the engine to the video view and waits for .readyToPlay before auto-playing.
    /// We observe the item status here (in addition to AVPlayerEngine's own observation)
    /// because the VC needs to resize the window to match the video's native aspect ratio
    /// — that info is only available after the asset header is parsed.
    private func playWithEngine(_ engine: AVPlayerEngine, url: URL, fallbackRemux: Bool = false) {
        dlog(.player, "Opening: \(url.path)")
        engine.open(url: url)
        videoView.setPlayer(engine.player)
        controlBarView.setPlayer(engine.player)

        // Drop any prior observation so it can't fire on a stale closure
        // capturing the previous engine. Capture engine weakly inside the
        // new observation for the same reason.
        playbackStatusObservation = nil
        playbackStatusObservation = engine.player?.currentItem?.observe(\.status, options: [.new]) { [weak self, weak engine] item, _ in
            guard let engine = engine else { return }
            guard item.status == .readyToPlay else {
                if item.status == .failed {
                    wlog(.player, "Player item FAILED: \(item.error?.localizedDescription ?? "?")")
                    if fallbackRemux {
                        self?.remuxAndPlay(engine: engine, url: url)
                        return
                    }
                }
                return
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                dlog(.player, "Ready to play! Duration: \(engine.duration)s")
                self.controlBarView.setDuration(engine.duration)
                let autoPlay = UserDefaults.standard.bool(forKey: Defaults.autoPlayOnOpen)
                if autoPlay {
                    engine.play()
                    self.controlBarView.setPlaying(true)
                }

                // Resize window to fit video at up to 70% of screen
                if let videoSize = engine.videoSize {
                    self.hasResizedForCurrentFile = true
                    self.resizeWindowToFitVideo(videoSize)
                }
            }
        }
    }


    private func remuxAndPlay(engine: AVPlayerEngine, url: URL) {
        // Propagate AirPlay setting from caller's engine — the DV path opts out
        // of AVKit AirPlay since Samsung receivers don't decode DV via AVKit.
        let allowsExternal = engine.allowsExternalPlayback
        DispatchQueue.main.async {
            self.osdView.show(message: L("Loading…"), duration: 10.0)
        }
        let fullURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_full")
            .appendingPathExtension("mp4")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = (try? FFmpegBridge.remuxFile(url.path, toOutput: fullURL.path)) != nil
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Bail if the user opened a different file while remux was
                // running — otherwise the stale engine here would overwrite
                // the freshly-set one on `self.playerEngine`.
                guard self.currentFileURL == url else {
                    try? FileManager.default.removeItem(at: fullURL)
                    return
                }
                if ok {
                    // Tear the current observation down BEFORE swapping engines
                    // so its closure can't fire against the new engine.
                    self.playbackStatusObservation = nil
                    self.playerEngine?.stop()
                    let newEngine = AVPlayerEngine()
                    newEngine.allowsExternalPlayback = allowsExternal
                    self.playerEngine = newEngine
                    newEngine.delegate = self
                    self.playbackSourceURL = fullURL
                    self.dvRemuxOutputURL = fullURL
                    self.playWithEngine(newEngine, url: fullURL)
                } else {
                    try? FileManager.default.removeItem(at: fullURL)
                    self.osdView.show(message: L("Failed to open file"))
                }
            }
        }
    }

    func togglePlayPause() {
        if let engine = playerEngine {
            if engine.isPlaying { engine.pause(); osdView.show(message: L("Paused")) }
            else { engine.play(); osdView.show(message: L("Playing")) }
            controlBarView.setPlaying(engine.isPlaying)
        } else if let engine = vlcEngine {
            if engine.isPlaying { engine.pause(); osdView.show(message: L("Paused")) }
            else { engine.play(); osdView.show(message: L("Playing")) }
            controlBarView.setPlaying(engine.isPlaying)
        }    }

    func seek(by seconds: Double) {
        var currentBefore: Double = 0
        var dur: Double = 0
        if let engine = playerEngine {
            currentBefore = engine.currentTime
            dur = engine.duration
            engine.seek(by: seconds)
        } else if let engine = vlcEngine {
            currentBefore = engine.currentTime
            dur = engine.duration
            engine.seek(by: seconds)
        }
        let expectedTime = max(0, min(dur, currentBefore + seconds))
        let pct = dur > 0 ? Int(expectedTime / dur * 100) : 0
        let cur = formatSeekTime(expectedTime)
        let total = formatSeekTime(dur)
        osdView.show(message: String(format: L("Seek to %@ / %@ (%d%%)"), cur, total, pct))
    }

    private func formatSeekTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    func adjustVolume(by delta: Float) {
        let maxVol: Float = UserDefaults.standard.bool(forKey: Defaults.extendedVolume) ? 2.0 : 1.0
        var v: Float = 1
        if let engine = playerEngine {
            v = max(0, min(maxVol, engine.volume + delta)); engine.volume = v
        } else if let engine = vlcEngine {
            v = max(0, min(maxVol, engine.volume + delta)); engine.volume = v
        }
        controlBarView.setVolume(v)
        let icon = v == 0 ? "speaker.slash.fill" : (v < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill")
        osdView.showBar(icon: icon, fraction: Double(v / maxVol))
    }

    func toggleMute() {
        if let engine = playerEngine {
            engine.isMuted.toggle()
            controlBarView.setMuted(engine.isMuted)
            osdView.show(message: engine.isMuted ? L("Muted") : L("Unmuted"))
        } else if let engine = vlcEngine {
            engine.isMuted.toggle()
            controlBarView.setMuted(engine.isMuted)
            osdView.show(message: engine.isMuted ? L("Muted") : L("Unmuted"))
        }    }

    func adjustSpeed(by delta: Float) {
        let currentRate: Float
        if let engine = playerEngine { currentRate = engine.rate }
        else if let engine = vlcEngine { currentRate = engine.rate }
        else { return }
        let newRate = max(0.25, min(4.0, currentRate + delta))
        setSpeed(newRate)
    }

    func setSpeed(_ speed: Float) {
        playerEngine?.rate = speed
        vlcEngine?.rate = speed
        controlBarView.setSpeed(speed)
        osdView.show(message: String(format: L("Speed: %.2fx"), speed))
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

    func showOSD(_ message: String, duration: TimeInterval = 1.5) {
        osdView.show(message: message, duration: duration)
    }

    func showAirPlayPicker() {
        controlBarView.showAirPlayPicker()

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self = self,
                  let player = self.playerEngine?.player,
                  !player.isExternalPlaybackActive else { return }
            if NSScreen.screens.count > 1 {
                self.moveToExternalDisplay()
            }
        }
    }

    // MARK: - Subtitle Operations

    func loadSubtitleFile(_ url: URL) {
        subtitleManager.loadSubtitle(from: url)
        osdView.show(message: String(format: L("Subtitle loaded: %@"), url.lastPathComponent))
    }

    func toggleSubtitleVisibility() {
        subtitleManager.toggleVisibility()
        if subtitleManager.isVisible {
            osdView.show(message: L("Subtitles visible"))
        } else {
            subtitleOverlayView.setText(nil)
            osdView.show(message: L("Subtitles hidden"))
        }
    }

    func adjustSubtitleDelay(by delta: Double) {
        subtitleManager.adjustDelay(by: delta)
        osdView.show(message: String(format: L("Subtitle delay: %.1fs"), subtitleManager.delay))
    }

    func resetSubtitleDelay() {
        subtitleManager.delay = 0
        osdView.show(message: L("Subtitle delay reset"))
    }

    // MARK: - Screenshot

    func saveScreenshot() {
        ScreenshotSaver.save(playerEngine: playerEngine, vlcEngine: vlcEngine) { [weak self] result in
            switch result {
            case .saved(let dir):
                self?.osdView.show(message: String(format: L("Screenshot saved to %@"), dir))
            case .failed:
                self?.osdView.show(message: L("Screenshot failed"))
            case .noVideo:
                self?.osdView.show(message: L("No video playing"))
            }
        }
    }

    // MARK: - Seek & A-B Loop

    func seekToAbsoluteTime(_ seconds: Double) {
        playerEngine?.seekTo(time: seconds)
        vlcEngine?.seekTo(time: seconds)
        osdView.show(message: String(format: L("Jump to %@"), formatSeekTime(seconds)))
    }

    func toggleABLoop() {
        let currentSeconds: Double
        if let engine = playerEngine {
            currentSeconds = engine.currentTime
        } else if let engine = vlcEngine {
            currentSeconds = engine.currentTime
        } else {
            return
        }
        let cmTime = CMTimeMakeWithSeconds(currentSeconds, preferredTimescale: 600)
        abLoopController.toggle(currentTime: cmTime)
        switch abLoopController.state {
        case .inactive:
            osdView.show(message: L("A-B Loop cleared"))
        case .settingA:
            osdView.show(message: L("A point set"))
        case .active:
            osdView.show(message: L("A-B Loop active"))
        }
    }

    // MARK: - Video Size & Transform

    func setVideoWindowSize(scale: CGFloat) {
        guard let window = view.window, let videoSize = playerEngine?.videoSize ?? vlcEngine?.videoSize else {
            osdView.show(message: L("No video loaded"))
            return
        }
        let newSize = NSSize(width: videoSize.width * scale, height: videoSize.height * scale)
        window.setContentSize(newSize)
        window.center()
        osdView.show(message: scale == 1 ? L("Original size") : String(format: L("%.0f%% size"), scale * 100))
    }

    func fitWindowToScreen() {
        guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        window.setFrame(frame, display: true, animate: true)
        osdView.show(message: L("Fit to screen"))
    }

    func toggleFillScreen() {
        isFillScreen.toggle()
        videoView.setVideoGravity(isFillScreen ? .resizeAspectFill : .resizeAspect)
        osdView.show(message: isFillScreen ? L("Fill screen") : L("Fit to screen"))
    }

    func setAspectRatio(_ name: String) {
        guard let window = view.window else { return }
        switch name {
        case "4:3":   window.contentAspectRatio = NSSize(width: 4, height: 3)
        case "16:9":  window.contentAspectRatio = NSSize(width: 16, height: 9)
        case "16:10": window.contentAspectRatio = NSSize(width: 16, height: 10)
        case "2.35:1": window.contentAspectRatio = NSSize(width: 235, height: 100)
        case "2.39:1": window.contentAspectRatio = NSSize(width: 239, height: 100)
        default:
            window.resizeIncrements = NSSize(width: 1, height: 1)
            window.contentAspectRatio = NSSize(width: 0, height: 0)
        }
        osdView.show(message: String(format: L("Aspect ratio: %@"), name))
    }

    func rotateVideo(by degrees: CGFloat) {
        videoRotation += degrees
        if videoRotation >= 360 { videoRotation -= 360 }
        if videoRotation < 0 { videoRotation += 360 }
        updateVideoTransform()
        osdView.show(message: String(format: L("Rotate: %d°"), Int(videoRotation)))
    }

    func flipVideo(horizontal: Bool) {
        if horizontal {
            videoFlippedH.toggle()
        } else {
            videoFlippedV.toggle()
        }
        updateVideoTransform()
        osdView.show(message: horizontal ? L("Flip horizontal") : L("Flip vertical"))
    }

    func revertVideoTransform() {
        videoRotation = 0
        videoFlippedH = false
        videoFlippedV = false
        updateVideoTransform()
        osdView.show(message: L("Transform reset"))
    }

    private func updateVideoTransform() {
        var t = CATransform3DIdentity
        t = CATransform3DRotate(t, videoRotation * .pi / 180, 0, 0, 1)
        if videoFlippedH { t = CATransform3DScale(t, -1, 1, 1) }
        if videoFlippedV { t = CATransform3DScale(t, 1, -1, 1) }
        videoView.setLayerTransform(t)
    }

    // MARK: - Picture in Picture

    func togglePiP() {
        if pipController == nil, let layer = videoView.getPlayerLayer() {
            pipController = AVPictureInPictureController(playerLayer: layer)
        }
        guard let pip = pipController else {
            osdView.show(message: L("PiP not available"))
            return
        }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    // MARK: - Frame Stepping

    func stepFrame(forward: Bool) {
        if let engine = playerEngine {
            engine.stepFrame(forward: forward)
            controlBarView.setPlaying(false)
            osdView.show(message: forward ? L("Frame ▶") : L("◀ Frame"))
        } else if let engine = vlcEngine, forward {
            engine.stepFrame()
            controlBarView.setPlaying(false)
            osdView.show(message: L("Frame ▶"))
        }
    }

    // MARK: - Chapter Navigation

    func seekToChapter(at index: Int) {
        guard index >= 0 && index < chapters.count,
              let startTime = chapters[index]["startTime"] as? Double else { return }
        let title = chapters[index]["title"] as? String ?? "Chapter \(index + 1)"
        playerEngine?.seekTo(time: startTime)
        vlcEngine?.seekTo(time: startTime)
        osdView.show(message: String(format: L("Chapter: %@"), title))
    }

    func seekToNextChapter() {
        let current = playerEngine?.currentTime ?? vlcEngine?.currentTime ?? 0
        if let next = ChapterNavigation.nextChapterIndex(currentTime: current, chapters: chapters) {
            seekToChapter(at: next)
        } else {
            osdView.show(message: L("No next chapter"))
        }
    }

    func seekToPreviousChapter() {
        let current = playerEngine?.currentTime ?? vlcEngine?.currentTime ?? 0
        if let prev = ChapterNavigation.previousChapterIndex(currentTime: current, chapters: chapters) {
            seekToChapter(at: prev)
        } else {
            osdView.show(message: L("No previous chapter"))
        }
    }

    // MARK: - Audio EQ

    func applyEQPreset(_ index: Int) {
        vlcEngine?.setEqualizer(presetIndex: index)
    }

    // MARK: - Audio Sync

    func adjustAudioDelay(by delta: Double) {
        audioDelayOffset += delta
        vlcEngine?.setAudioDelay(seconds: audioDelayOffset)
        osdView.show(message: String(format: L("Audio delay: %+.1fs"), audioDelayOffset))
    }

    func resetAudioDelay() {
        audioDelayOffset = 0
        vlcEngine?.setAudioDelay(seconds: 0)
        osdView.show(message: L("Audio delay reset"))
    }

    // MARK: - Playlist Panel

    func togglePlaylistPanel() {
        if playlistPanel == nil {
            let panel = PlaylistPanelView()
            panel.delegate = self
            panel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(panel)

            let trailing = panel.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            playlistPanelConstraint = trailing
            NSLayoutConstraint.activate([
                trailing,
                panel.topAnchor.constraint(equalTo: view.topAnchor),
                panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                panel.widthAnchor.constraint(equalToConstant: 250),
            ])
            playlistPanel = panel
        }

        guard let panel = playlistPanel else { return }
        panel.setItems(playlistManager.items)
        panel.currentIndex = playlistManager.currentIndex

        let showing = panel.isHidden
        if showing {
            panel.isHidden = false
        } else {
            panel.isHidden = true
        }
    }

    // MARK: - Playlist

    func setRepeatMode(_ mode: RepeatMode) {
        playlistManager.repeatMode = mode
        osdView.show(message: String(format: L("Repeat: %@"), mode.rawValue))
    }

    func toggleShuffle() {
        playlistManager.shuffle.toggle()
        osdView.show(message: playlistManager.shuffle ? L("Shuffle on") : L("Shuffle off"))
    }

    func playNextTrack() {
        guard let url = playlistManager.next() else {
            osdView.show(message: L("No next track"))
            return
        }
        onFileDropped?(url)
    }

    func playPreviousTrack() {
        guard let url = playlistManager.previous() else {
            osdView.show(message: L("No previous track"))
            return
        }
        onFileDropped?(url)
    }
}

// MARK: - ControlBarDelegate

extension PlayerViewController: ControlBarDelegate {
    func controlBarPlayPauseClicked() {
        togglePlayPause()
    }

    func controlBarSeekRequested(to fraction: Double) {
        if let engine = playerEngine {
            engine.seekToFraction(fraction)
        } else if let engine = vlcEngine {
            engine.seekToFraction(fraction)
        }
    }

    func controlBarVolumeChanged(to volume: Float) {
        playerEngine?.volume = volume
        vlcEngine?.volume = volume
        osdView.show(message: String(format: L("Volume: %d%%"), Int(volume * 100)))
    }

    func controlBarSpeedChanged(to speed: Float) {
        setSpeed(speed)
    }

    func controlBarSeekBackward() {
        seek(by: -shortSeek)
    }

    func controlBarSeekForward() {
        seek(by: shortSeek)
    }

    func controlBarPreviousClicked() {
        playPreviousTrack()
    }

    func controlBarNextClicked() {
        playNextTrack()
    }

    func controlBarAirPlayRequested() {
        if NSScreen.screens.count > 1 {
            moveToExternalDisplay()
            return
        }

        // Dolby Vision casting isn't supported: AVKit AirPlay silently fails
        // against Samsung's AirPlay 2 receiver, libvlc chromecast re-encodes
        // to SDR (wrong colors), and DLNA only accepts plain MP4 with moov at
        // the start — which can only be produced by a full offline transcode.
        // See CLAUDE.md "Dolby Vision casting (currently unsupported)" for
        // the full investigation and revival path.
        if playerEngine != nil, currentFileIsDolbyVision {
            osdView.show(message: L("Casting Dolby Vision isn't supported. Play locally instead."), duration: 4.0)
            return
        }

        if playerEngine != nil {
            showAirPlayPicker()
            return
        }

        guard let vlc = vlcEngine else { return }
        let renderers = vlc.discoveredRenderers
        if renderers.isEmpty {
            osdView.show(message: L("Searching for devices…"), duration: 3.0)
            vlc.startRendererDiscovery()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self, let vlc = self.vlcEngine else { return }
                self.showRendererMenu(renderers: vlc.discoveredRenderers)
            }
            return
        }
        showRendererMenu(renderers: renderers)
    }

    private func showRendererMenu(renderers: [VLCPlayerEngine.RendererInfo]) {
        if renderers.isEmpty {
            osdView.show(message: L("No devices found"), duration: 3.0)
            return
        }

        let menu = NSMenu(title: "Renderer")
        for (index, renderer) in renderers.enumerated() {
            let item = NSMenuItem(title: renderer.name, action: #selector(rendererSelected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }

        let buttonFrame = controlBarView.castButtonFrameInWindow()
        let localPoint = view.convert(NSPoint(x: buttonFrame.midX, y: buttonFrame.maxY + 4), from: nil)
        menu.popUp(positioning: nil, at: localPoint, in: view)
    }

    @objc private func rendererSelected(_ sender: NSMenuItem) {
        guard let vlc = vlcEngine, currentFileURL != nil else { return }
        let index = sender.tag
        guard index < vlc.discoveredRenderers.count else { return }

        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.castingManager.stop()
        }

        let renderer = vlc.discoveredRenderers[index]
        let savedTime = vlc.currentTime

        // Set renderer then restart playback without releasing the player
        vlc.setRenderer(renderer)
        if let p = vlc.player {
            libvlc_media_player_stop(p)
            libvlc_media_player_play(p)
            if savedTime > 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    vlc.seekTo(time: savedTime)
                }
            }
        }
        osdView.show(message: "Casting to \(renderer.name)…", duration: 3.0)
    }
}

// MARK: - AVPlayerEngineDelegate

extension PlayerViewController: AVPlayerEngineDelegate {
    func playerEngineTimeDidChange(current: Double, duration: Double) {
        controlBarView.updateTime(current: current, duration: duration)

        if subtitleManager.hasSubtitles, subtitleManager.isVisible,
           let entry = subtitleManager.subtitle(at: current) {
            if let attr = entry.attributedText {
                subtitleOverlayView.setAttributedText(attr)
            } else {
                subtitleOverlayView.setText(entry.text)
            }
        } else {
            subtitleOverlayView.setText(nil)
        }

        if let player = playerEngine?.player {
            abLoopController.checkLoop(currentTime: player.currentTime())
        }

        (NSApp.delegate as? AppDelegate)?.nowPlayingController.updateTime(
            elapsed: current, rate: Double(playerEngine?.rate ?? 1.0)
        )
    }

    func playerEngineDidFinishPlaying() {
        controlBarView.setPlaying(false)
        let action = UserDefaults.standard.integer(forKey: Defaults.mediaEndAction)
        switch action {
        case 0: // Nothing
            (NSApp.delegate as? AppDelegate)?.nowPlayingController.clear()
        case 1: // Close Media
            playerEngine?.stop()
            welcomeView.isHidden = false
            controlBarView.setVideoActive(false)
            (NSApp.delegate as? AppDelegate)?.nowPlayingController.clear()
        case 2: // Play Next
            playNextTrack()
        case 3: // Loop
            playerEngine?.seekTo(time: 0)
            playerEngine?.play()
            controlBarView.setPlaying(true)
        default: break
        }
    }

    func playerEngineDidUpdateStatus(isPlaying: Bool) {
        controlBarView.setPlaying(isPlaying)
        onPlaybackStateChanged?(isPlaying)
        (NSApp.delegate as? AppDelegate)?.nowPlayingController.updatePlaybackState(isPlaying: isPlaying)
    }

    func playerEngineExternalPlaybackChanged(isActive: Bool) {
        if isActive {
            osdView.show(message: L("AirPlay: Playing on TV"), duration: 3.0)
        } else {
            osdView.show(message: L("AirPlay: Local playback"))
        }
    }

    /// Move the player window to an external display and enter fullscreen.
    /// Works with HDMI, AirPlay displays, and sidecar — any screen that macOS
    /// recognizes. Falls back to a helpful message if no external screen exists.
    func moveToExternalDisplay() {
        guard let window = view.window else { return }
        guard let externalScreen = NSScreen.screens.first(where: { $0 != NSScreen.main }) else {
            osdView.show(message: L("No external display found — add one via System Settings > Displays"), duration: 3.0)
            return
        }
        window.setFrame(externalScreen.frame, display: true, animate: true)
        if !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        osdView.show(message: "Playing on \(externalScreen.localizedName)", duration: 3.0)
    }
}

// MARK: - VLCPlayerEngineDelegate

extension PlayerViewController: VLCPlayerEngineDelegate {
    func vlcEngineTimeDidChange(current: Double, duration: Double) {
        if !hasResizedForCurrentFile, let videoSize = vlcEngine?.videoSize, videoSize.width > 0 {
            hasResizedForCurrentFile = true
            resizeWindowToFitVideo(videoSize)
        }

        controlBarView.updateTime(current: current, duration: duration)

        if subtitleManager.hasSubtitles, subtitleManager.isVisible,
           let entry = subtitleManager.subtitle(at: current) {
            if let attr = entry.attributedText {
                subtitleOverlayView.setAttributedText(attr)
            } else {
                subtitleOverlayView.setText(entry.text)
            }
        } else {
            subtitleOverlayView.setText(nil)
        }

        let cmTime = CMTimeMakeWithSeconds(current, preferredTimescale: 600)
        abLoopController.checkLoop(currentTime: cmTime)

        (NSApp.delegate as? AppDelegate)?.nowPlayingController.updateTime(
            elapsed: current, rate: Double(vlcEngine?.rate ?? 1.0)
        )
    }
    func vlcEngineDidFinishPlaying() {
        controlBarView.setPlaying(false)
        (NSApp.delegate as? AppDelegate)?.nowPlayingController.updatePlaybackState(isPlaying: false)
        let action = UserDefaults.standard.integer(forKey: Defaults.mediaEndAction)
        switch action {
        case 0: // Nothing — match AVPlayer twin (clear now-playing, keep frame)
            (NSApp.delegate as? AppDelegate)?.nowPlayingController.clear()
        case 1: // Close Media
            vlcEngine?.stop()
            // Detach VLC's render layer from videoView; otherwise the last
            // frame stays on top of welcomeView and the user sees a frozen
            // image instead of the idle state.
            videoView.subviews.forEach { $0.removeFromSuperview() }
            vlcEngine = nil
            welcomeView.isHidden = false
            welcomeView.refreshRecents()
            controlBarView.setVideoActive(false)
            (NSApp.delegate as? AppDelegate)?.nowPlayingController.clear()
        case 2: // Play Next
            playNextTrack()
        case 3: // Loop
            vlcEngine?.seekTo(time: 0)
            vlcEngine?.play()
            controlBarView.setPlaying(true)
        default:
            (NSApp.delegate as? AppDelegate)?.nowPlayingController.clear()
        }
    }
    func vlcEngineDidUpdateStatus(isPlaying: Bool) {
        controlBarView.setPlaying(isPlaying)
        onPlaybackStateChanged?(isPlaying)
        (NSApp.delegate as? AppDelegate)?.nowPlayingController.updatePlaybackState(isPlaying: isPlaying)
    }
}

// MARK: - AudioPassthroughManagerDelegate

extension PlayerViewController: AudioPassthroughManagerDelegate {
    func passthroughStateChanged(isActive: Bool, deviceName: String?) {
        if isActive {
            osdView.show(message: String(format: L("Passthrough: ON (%@)"), deviceName ?? L("Unknown")))
        } else {
            osdView.show(message: L("Passthrough: OFF"))
        }
    }

    func togglePassthrough() {
        passthroughManager.toggle()
    }
}

// MARK: - PlaylistPanelDelegate

extension PlayerViewController: PlaylistPanelDelegate {
    func playlistPanel(_ panel: PlaylistPanelView, didSelectItemAt index: Int) {
        guard index < playlistManager.items.count else { return }
        let url = playlistManager.items[index]
        _ = playlistManager.selectItem(at: index)
        openFile(url: url)
    }

    func playlistPanel(_ panel: PlaylistPanelView, didRemoveItemAt index: Int) {
        playlistManager.removeItem(at: index)
        panel.setItems(playlistManager.items)
    }
}

// MARK: - ABLoopDelegate

extension PlayerViewController: ABLoopDelegate {
    func abLoopStateChanged(_ state: ABLoopState) {}

    func abLoopShouldSeek(to time: CMTime) {
        let seconds = time.seconds
        if let engine = playerEngine {
            engine.seekTo(time: seconds)
        } else if let engine = vlcEngine {
            engine.seekTo(time: seconds)
        }
    }
}

/// Separate view for drag-and-drop so the root view owns the drag registration
/// independently of PlayerViewController's subview hierarchy.
// MARK: - Drag and Drop View

class DragDropView: NSView {
    var onFileDropped: ((URL) -> Void)?
    var onArrowKey: ((Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func keyDown(with event: NSEvent) {
        // Must override to prevent system beep on arrow keys
        if let chars = event.charactersIgnoringModifiers,
           let scalar = chars.unicodeScalars.first?.value,
           scalar >= NSUpArrowFunctionKey && scalar <= NSRightArrowFunctionKey {
            onArrowKey?(Int(scalar))
        } else {
            super.keyDown(with: event)
        }
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
