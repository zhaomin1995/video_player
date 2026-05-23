import Cocoa

class PlayerWindow: NSWindow {
    private var initialMouseLocation: NSPoint = .zero
    private var isMovingWindow = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let windowSize = NSSize(width: 960, height: 540)
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
        isMovableByWindowBackground = false
        backgroundColor = .black
        minSize = NSSize(width: 480, height: 270)
        collectionBehavior = [.fullScreenPrimary]
        acceptsMouseMovedEvents = true
        tabbingMode = .disallowed
    }

    func setAspectRatio(_ ratio: NSSize) {
        // Don't lock contentAspectRatio — let the user resize freely.
        // AVPlayerLayer handles letterboxing with .resizeAspect.
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
