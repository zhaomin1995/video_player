/// Borderless player window styled after Movist Pro. Uses .fullSizeContentView so
/// the video extends behind the title bar for an immersive look, while keeping
/// .titled to preserve the system close/minimize/fullscreen buttons.
import Cocoa

class PlayerWindow: NSWindow {
    var onFileDropped: ((URL) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        let fullScreen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let visible = NSScreen.main?.visibleFrame ?? fullScreen
        let w = fullScreen.width * 0.7
        let h = fullScreen.height * 0.7
        let x = visible.origin.x + (visible.width - w) / 2
        let y = visible.origin.y + (visible.height - h) / 2
        let contentRect = NSRect(x: x, y: y, width: w, height: h)

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isRestorable = false
        titlebarAppearsTransparent = UserDefaults.standard.bool(forKey: Defaults.transparentTitleBar)
        titleVisibility = .hidden
        isMovableByWindowBackground = false
        backgroundColor = .black
        minSize = NSSize(width: 480, height: 270)
        collectionBehavior = [.fullScreenPrimary]
        acceptsMouseMovedEvents = true
        tabbingMode = .disallowed
        registerForDraggedTypes([.fileURL])
    }

    func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return [] }
        return .copy
    }

    func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let url = urls.first else { return false }
        onFileDropped?(url)
        return true
    }

    func toggleAlwaysOnTop() {
        if level == .floating {
            level = .normal
        } else {
            level = .floating
        }
    }
}
