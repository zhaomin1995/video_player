import Cocoa

class SeekSliderView: NSView {
    var onSeek: ((Double) -> Void)?

    private var progress: Double = 0
    private var isDragging = false
    private var dragProgress: Double = 0

    private let trackHeight: CGFloat = 4
    private let knobSize: CGFloat = 12
    private let expandedTrackHeight: CGFloat = 6
    private var isHovered = false

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let currentTrackHeight = isHovered || isDragging ? expandedTrackHeight : trackHeight
        let trackY = (bounds.height - currentTrackHeight) / 2
        let trackWidth = bounds.width - knobSize
        let trackX = knobSize / 2

        // Track background
        let trackRect = NSRect(x: trackX, y: trackY, width: trackWidth, height: currentTrackHeight)
        context.setFillColor(NSColor.white.withAlphaComponent(0.3).cgColor)
        let bgPath = NSBezierPath(roundedRect: trackRect, xRadius: currentTrackHeight / 2, yRadius: currentTrackHeight / 2)
        bgPath.fill()

        // Progress fill
        let currentProgress = isDragging ? dragProgress : progress
        let fillWidth = trackWidth * currentProgress
        if fillWidth > 0 {
            let fillRect = NSRect(x: trackX, y: trackY, width: fillWidth, height: currentTrackHeight)
            context.setFillColor(NSColor.systemBlue.cgColor)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: currentTrackHeight / 2, yRadius: currentTrackHeight / 2)
            fillPath.fill()
        }

        // Knob
        if isHovered || isDragging {
            let knobX = trackX + fillWidth - knobSize / 2
            let knobY = (bounds.height - knobSize) / 2
            let knobRect = NSRect(x: knobX, y: knobY, width: knobSize, height: knobSize)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: knobRect)
        }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        updateDragProgress(with: event)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        updateDragProgress(with: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        updateDragProgress(with: event)
        progress = dragProgress
        onSeek?(progress)
        needsDisplay = true
    }

    private func updateDragProgress(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let trackX = knobSize / 2
        let trackWidth = bounds.width - knobSize
        dragProgress = max(0, min(1, Double((location.x - trackX) / trackWidth)))
    }

    func setProgress(_ value: Double) {
        guard !isDragging else { return }
        progress = max(0, min(1, value))
        needsDisplay = true
    }
}
