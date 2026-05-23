/// Borderless player window styled after Movist Pro. Uses .fullSizeContentView so
/// the video extends behind the title bar for an immersive look, while keeping
/// .titled to preserve the system close/minimize/fullscreen buttons.
import Cocoa

class PlayerWindow: NSWindow {
    private var initialMouseLocation: NSPoint = .zero
    private var isMovingWindow = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowSize = NSSize(width: screenFrame.width * 0.7, height: screenFrame.height * 0.7)
        let origin = NSPoint(
            x: (screenFrame.width - windowSize.width) / 2,
            y: (screenFrame.height - windowSize.height) / 2
        )
        let contentRect = NSRect(origin: origin, size: windowSize)

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        // Disabled so drag-to-seek on the video area doesn't accidentally move the window
        isMovableByWindowBackground = false
        backgroundColor = .black
        // 480x270 = 16:9 minimum to prevent the control bar from being clipped
        minSize = NSSize(width: 480, height: 270)
        collectionBehavior = [.fullScreenPrimary]
        // Required for mouseMoved events (used to show/hide controls on hover)
        acceptsMouseMovedEvents = true
        tabbingMode = .disallowed
    }

    /// Intentionally a no-op: locking contentAspectRatio prevents free resizing.
    /// AVPlayerLayer's .resizeAspect gravity handles letterboxing automatically.
    func setAspectRatio(_ ratio: NSSize) {
    }

    func clearAspectRatio() {
        contentResizeIncrements = NSSize(width: 1, height: 1)
    }

    override func performDrag(with event: NSEvent) {
        // Allow window dragging from video area
    }

    func toggleAlwaysOnTop() {
        if level == .floating {
            level = .normal
        } else {
            level = .floating
        }
    }
}
