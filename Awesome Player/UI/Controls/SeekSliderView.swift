import Cocoa
import AVFoundation

class SeekSliderView: NSView {
    var onSeek: ((Double) -> Void)?
    var duration: Double = 0

    private var progress: Double = 0
    private var isDragging = false
    private var dragProgress: Double = 0
    private var seekSuppressUntil: Date = .distantPast
    private var lastSoughtFraction: Double = -1
    private var lastScrubTime: Date = .distantPast
    private var didScrubOnMouseDown = false

    private let trackHeight: CGFloat = 4
    private let knobSize: CGFloat = 12
    private let expandedTrackHeight: CGFloat = 6
    private var isHovered = false

    private var trackingArea: NSTrackingArea?

    // Tooltip — added directly to the window's contentView to avoid clipping
    private var tooltipWindow: NSPanel?
    private var tooltipLabel: NSTextField?

    // Thumbnail preview
    private var thumbnailWindow: NSPanel?
    private var thumbnailView: NSImageView?
    private var imageGenerator: AVAssetImageGenerator?
    /// LRU thumbnail cache with byte-cost ceiling instead of a hard count
    /// ceiling. Earlier code wiped the whole dict at 150 entries — long
    /// films re-generated thumbs constantly on repeat scrubs. NSCache
    /// evicts the least-recently-used entries automatically when the
    /// cost limit is hit and survives memory pressure events.
    private lazy var thumbnailCache: NSCache<NSNumber, NSImage> = {
        let c = NSCache<NSNumber, NSImage>()
        c.totalCostLimit = 24 * 1024 * 1024  // ~24 MB of thumbnails
        return c
    }()
    private var pendingThumbnailTime: Double?

    var currentAsset: AVAsset? {
        didSet {
            thumbnailCache.removeAllObjects()
            if let asset = currentAsset {
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 240, height: 135)
                gen.requestedTimeToleranceBefore = CMTimeMake(value: 1, timescale: 1)
                gen.requestedTimeToleranceAfter = CMTimeMake(value: 1, timescale: 1)
                imageGenerator = gen
            } else {
                imageGenerator = nil
            }
        }
    }

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
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp],
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
        hideTooltip()
        hideThumbnail()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        guard duration > 0 else { return }
        let location = convert(event.locationInWindow, from: nil)
        let fraction = fractionForX(location.x)
        let time = fraction * duration
        showTooltip(at: event.locationInWindow, time: time)
        requestThumbnail(at: time, screenPoint: event.locationInWindow)
    }

    private func fractionForX(_ localX: CGFloat) -> Double {
        let trackX = knobSize / 2
        let trackWidth = bounds.width - knobSize
        return max(0, min(1, Double((localX - trackX) / trackWidth)))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let currentTrackHeight = isHovered || isDragging ? expandedTrackHeight : trackHeight
        let trackY = (bounds.height - currentTrackHeight) / 2
        let trackWidth = bounds.width - knobSize
        let trackX = knobSize / 2

        let trackRect = NSRect(x: trackX, y: trackY, width: trackWidth, height: currentTrackHeight)
        context.setFillColor(NSColor.white.withAlphaComponent(0.3).cgColor)
        let bgPath = NSBezierPath(roundedRect: trackRect, xRadius: currentTrackHeight / 2, yRadius: currentTrackHeight / 2)
        bgPath.fill()

        let currentProgress = isDragging ? dragProgress : progress
        let fillWidth = trackWidth * currentProgress
        if fillWidth > 0 {
            let fillRect = NSRect(x: trackX, y: trackY, width: fillWidth, height: currentTrackHeight)
            context.setFillColor(NSColor.systemBlue.cgColor)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: currentTrackHeight / 2, yRadius: currentTrackHeight / 2)
            fillPath.fill()
        }

        if isHovered || isDragging {
            let knobX = trackX + fillWidth - knobSize / 2
            let knobY = (bounds.height - knobSize) / 2
            let knobRect = NSRect(x: knobX, y: knobY, width: knobSize, height: knobSize)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: knobRect)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        didScrubOnMouseDown = false
        updateDragProgress(with: event)
        needsDisplay = true
        scrubSeek()
        didScrubOnMouseDown = true
    }

    override func mouseDragged(with event: NSEvent) {
        updateDragProgress(with: event)
        needsDisplay = true

        if duration > 0 {
            let time = dragProgress * duration
            showTooltip(at: event.locationInWindow, time: time)
            requestThumbnail(at: time, screenPoint: event.locationInWindow)
        }
        // Live scrubbing — seek during drag, throttled to every 100ms
        let now = Date()
        if now.timeIntervalSince(lastScrubTime) >= 0.1 {
            scrubSeek()
        }
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        updateDragProgress(with: event)
        progress = dragProgress

        if !didScrubOnMouseDown || abs(dragProgress - lastSoughtFraction) > 0.001 {
            lastSoughtFraction = progress
            seekSuppressUntil = Date().addingTimeInterval(0.2)
            onSeek?(progress)
        } else {
            seekSuppressUntil = Date().addingTimeInterval(0.2)
        }

        didScrubOnMouseDown = false
        hideThumbnail()
        needsDisplay = true
    }

    private func scrubSeek() {
        lastScrubTime = Date()
        lastSoughtFraction = dragProgress
        seekSuppressUntil = Date().addingTimeInterval(0.2)
        onSeek?(dragProgress)
    }

    private func updateDragProgress(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        dragProgress = fractionForX(location.x)
    }

    func setProgress(_ value: Double) {
        guard !isDragging else { return }
        if Date() < seekSuppressUntil {
            if lastSoughtFraction >= 0 && abs(value - lastSoughtFraction) < 0.05 {
                seekSuppressUntil = .distantPast
                lastSoughtFraction = -1
            } else {
                return
            }
        }
        progress = max(0, min(1, value))
        needsDisplay = true
    }

    // MARK: - Tooltip (floating panel to avoid clipping)

    private func showTooltip(at windowPoint: NSPoint, time: Double) {
        guard let parentWindow = window else { return }

        if tooltipWindow == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 80, height: 24),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = false
            panel.ignoresMouseEvents = true

            let bg = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 28))
            bg.wantsLayer = true
            bg.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.9).cgColor
            bg.layer?.cornerRadius = 5

            let label = NSTextField(labelWithString: "")
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.textColor = .white
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            bg.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -4),
            ])

            panel.contentView = bg
            tooltipLabel = label
            tooltipWindow = panel
            parentWindow.addChildWindow(panel, ordered: .above)
        }

        guard let tip = tooltipWindow, let label = tooltipLabel else { return }

        let total = Int(time)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        label.stringValue = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)

        let tipWidth: CGFloat = h > 0 ? 80 : 60
        let screenPoint = parentWindow.convertPoint(toScreen: NSPoint(x: windowPoint.x, y: windowPoint.y))

        let sliderScreenY = parentWindow.convertPoint(toScreen: convert(NSPoint(x: 0, y: bounds.maxY), to: nil)).y

        let thumbnailOffset: CGFloat = (thumbnailWindow?.isVisible == true) ? 98 : 0
        let tipX = screenPoint.x - tipWidth / 2
        let tipY = sliderScreenY + 8 + thumbnailOffset

        tip.setFrame(NSRect(x: tipX, y: tipY, width: tipWidth, height: 28), display: true)
        tip.contentView?.frame = NSRect(x: 0, y: 0, width: tipWidth, height: 28)
        tip.orderFront(nil)
    }

    private func hideTooltip() {
        tooltipWindow?.orderOut(nil)
    }

    // MARK: - Thumbnail Preview (floating panel)

    private func requestThumbnail(at time: Double, screenPoint: NSPoint) {
        guard imageGenerator != nil else { return }

        let cacheKey = NSNumber(value: Int(time / 2))

        if let cached = thumbnailCache.object(forKey: cacheKey) {
            showThumbnail(cached, screenPoint: screenPoint)
            return
        }

        guard let gen = imageGenerator else { return }

        gen.cancelAllCGImageGeneration()
        pendingThumbnailTime = time
        let cmTime = CMTimeMakeWithSeconds(time, preferredTimescale: 600)

        gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: cmTime)]) { [weak self] _, cgImage, _, _, _ in
            guard let self = self, let cgImage = cgImage else { return }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            DispatchQueue.main.async {
                // Cost = approx bytes (RGBA8 width*height*4). Lets NSCache
                // size the working set against totalCostLimit instead of a
                // raw count, which mattered for 4K vs 720p thumbnails.
                let cost = Int(cgImage.width * cgImage.height * 4)
                self.thumbnailCache.setObject(image, forKey: cacheKey, cost: cost)
                if let pending = self.pendingThumbnailTime, abs(pending - time) < 3 {
                    self.showThumbnail(image, screenPoint: screenPoint)
                }
            }
        }
    }

    private func showThumbnail(_ image: NSImage, screenPoint: NSPoint) {
        guard let parentWindow = window else { return }
        let thumbWidth: CGFloat = 160
        let thumbHeight: CGFloat = 90

        if thumbnailWindow == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = true
            panel.ignoresMouseEvents = true

            let bg = NSView(frame: NSRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight))
            bg.wantsLayer = true
            bg.layer?.backgroundColor = NSColor(white: 0.05, alpha: 0.95).cgColor
            bg.layer?.cornerRadius = 6
            bg.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
            bg.layer?.borderWidth = 1

            let imageView = NSImageView(frame: NSRect(x: 3, y: 3, width: thumbWidth - 6, height: thumbHeight - 6))
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.autoresizingMask = [.width, .height]
            bg.addSubview(imageView)

            panel.contentView = bg
            thumbnailView = imageView
            thumbnailWindow = panel
            parentWindow.addChildWindow(panel, ordered: .above)
        }

        guard let thumb = thumbnailWindow, let imageView = thumbnailView else { return }

        imageView.image = image

        let sliderScreenPoint = parentWindow.convertPoint(toScreen: convert(NSPoint(x: 0, y: bounds.maxY), to: nil))
        let scrPt = parentWindow.convertPoint(toScreen: screenPoint)
        let thumbX = scrPt.x - thumbWidth / 2
        let thumbY = sliderScreenPoint.y + 8

        thumb.setFrame(NSRect(x: thumbX, y: thumbY, width: thumbWidth, height: thumbHeight), display: true)
        thumb.orderFront(nil)
    }

    private func hideThumbnail() {
        thumbnailWindow?.orderOut(nil)
        pendingThumbnailTime = nil
    }
}
