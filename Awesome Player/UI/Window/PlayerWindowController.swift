import Cocoa

class PlayerWindowController: NSWindowController {
    let playerViewController = PlayerViewController()
    let titleBarView = TitleBarView()
    private var titleBarTopConstraint: NSLayoutConstraint?
    private var mouseIdleTimer: Timer?
    private var controlsVisible = true
    private var globalMouseMonitor: Any?

    init() {
        let playerWindow = PlayerWindow()
        super.init(window: playerWindow)
        setupWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupWindow() {
        guard let window = window as? PlayerWindow else { return }
        window.contentViewController = playerViewController

        titleBarView.delegate = self
        titleBarView.setTitle("Awesome Player")
        titleBarView.translatesAutoresizingMaskIntoConstraints = false
        if let contentView = window.contentView {
            contentView.addSubview(titleBarView)

            let topConstraint = titleBarView.topAnchor.constraint(equalTo: contentView.topAnchor)
            titleBarTopConstraint = topConstraint

            NSLayoutConstraint.activate([
                topConstraint,
                titleBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                titleBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                titleBarView.heightAnchor.constraint(equalToConstant: 38),
            ])
        }

        playerViewController.onMouseMoved = { [weak self] in
            self?.showControls()
            self?.resetIdleTimer()
        }

        // Monitor mouse globally to detect when it leaves the window
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            let mouse = NSEvent.mouseLocation
            if !window.frame.contains(mouse) && self.controlsVisible {
                self.mouseIdleTimer?.invalidate()
                self.hideControls()
            }
        }

        playerViewController.onFileDropped = { [weak self] url in
            self?.openFile(url: url)
        }

        window.onFileDropped = { [weak self] url in
            self?.openFile(url: url)
        }

        playerViewController.onDoubleClick = { [weak self] in
            self?.toggleFullscreen()
        }

        // Start auto-hide timer when playback begins so controls fade
        // even if the user never moves the mouse after opening a file
        playerViewController.onPlaybackStateChanged = { [weak self] isPlaying in
            if isPlaying {
                self?.resetIdleTimer()
            } else {
                self?.mouseIdleTimer?.invalidate()
                self?.showControls()
            }
        }
    }

    func openFile(url: URL) {
        let filename = url.deletingPathExtension().lastPathComponent
        titleBarView.setTitle(filename)
        if url.isFileURL {
            RecentDocumentsMenuDelegate.addRecentFile(url)
        }
        playerViewController.openFile(url: url)
    }

    func toggleFullscreen() {
        // Restore cursor before toggling in case we're exiting fullscreen
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
        window?.toggleFullScreen(nil)
        resetIdleTimer()
    }

    private var cursorHidden = false

    private func showControls() {
        guard !controlsVisible else { return }
        controlsVisible = true
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            titleBarView.animator().alphaValue = 1.0
            playerViewController.showControlBar(animated: true)
        }
        window?.standardWindowButton(.closeButton)?.superview?.alphaValue = 1.0
    }

    private func hideControls() {
        guard controlsVisible, !playerViewController.isPaused else { return }
        controlsVisible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            titleBarView.animator().alphaValue = 0.0
            playerViewController.hideControlBar(animated: true)
        }
        window?.standardWindowButton(.closeButton)?.superview?.alphaValue = 0.0
        // Only hide cursor in fullscreen
        if window?.styleMask.contains(.fullScreen) == true, !cursorHidden {
            NSCursor.hide()
            cursorHidden = true
        }
    }

    private func resetIdleTimer() {
        mouseIdleTimer?.invalidate()
        let pref = UserDefaults.standard.integer(forKey: Defaults.fullscreenControlBar)
        // 0 = auto-hide 3s, 1 = auto-hide 5s, 2 = always show
        if pref == 2 { return }
        let interval: TimeInterval = pref == 1 ? 5.0 : 3.0
        mouseIdleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.hideControls()
        }
    }
}

extension PlayerWindowController: TitleBarDelegate {
    func titleBarPinToggled(isPinned: Bool) {
        (window as? PlayerWindow)?.toggleAlwaysOnTop()
    }
}
