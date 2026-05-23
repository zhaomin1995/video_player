import Cocoa

class PlayerWindowController: NSWindowController {
    let playerViewController = PlayerViewController()
    private let titleBarView = TitleBarView()
    private var titleBarTopConstraint: NSLayoutConstraint?
    private var mouseIdleTimer: Timer?
    private var controlsVisible = true

    init() {
        let playerWindow = PlayerWindow()
        super.init(window: playerWindow)
        setupWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

        playerViewController.onFileDropped = { [weak self] url in
            self?.openFile(url: url)
        }

        playerViewController.onDoubleClick = { [weak self] in
            self?.toggleFullscreen()
        }
    }

    func openFile(url: URL) {
        let filename = url.deletingPathExtension().lastPathComponent
        titleBarView.setTitle(filename)
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
        mouseIdleTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.hideControls()
        }
    }
}

extension PlayerWindowController: TitleBarDelegate {
    func titleBarPinToggled(isPinned: Bool) {
        (window as? PlayerWindow)?.toggleAlwaysOnTop()
    }
}
