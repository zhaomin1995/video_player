import Cocoa

/// Drag-to-select crop overlay. Sits on top of the video while in crop mode.
/// Draws a semi-transparent black mask everywhere EXCEPT the selected rect,
/// so the selection reads as "the part you'll keep." Apply/Cancel/Reset
/// floating buttons hang in the bottom-right.
///
/// Coord conversion to source video: the drag rect is in our view's local
/// coordinate space, which is in points and matches the video view. The video
/// view shows the video at `videoSize` (in source pixels) using
/// `AVLayerVideoGravity.resizeAspect` / libvlc's native aspect — so we need to
/// figure out where the actual video frame sits inside our view bounds
/// (letterbox/pillarbox), then map the drag rect into source pixel space.
/// See `cropGeometry()`.
final class CropOverlayView: NSView {

    /// Called with libvlc-format crop string ("WxH+X+Y" in source-pixel units)
    /// when the user clicks Apply. nil means cancel/reset.
    var onApply: ((String?) -> Void)?
    /// Pull the active video's native dimensions so we can map a drag rect
    /// in our coordinate space back to source pixels for libvlc/AVPlayer.
    var videoSize: () -> NSSize? = { nil }

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero

    private let applyButton = NSButton(title: "", target: nil, action: nil)
    private let cancelButton = NSButton(title: "", target: nil, action: nil)
    private let resetButton = NSButton(title: "", target: nil, action: nil)
    private let infoLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupButtons()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func setupButtons() {
        applyButton.title = L("Apply Crop")
        applyButton.bezelStyle = .rounded
        applyButton.target = self
        applyButton.action = #selector(applyTapped)
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.appearance = NSAppearance(named: .darkAqua)

        cancelButton.title = L("Cancel")
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.appearance = NSAppearance(named: .darkAqua)

        resetButton.title = L("Reset")
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetTapped)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.appearance = NSAppearance(named: .darkAqua)

        infoLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        infoLabel.textColor = .white
        infoLabel.alignment = .center
        infoLabel.wantsLayer = true
        infoLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.isHidden = true

        addSubview(infoLabel)
        addSubview(resetButton)
        addSubview(cancelButton)
        addSubview(applyButton)

        NSLayoutConstraint.activate([
            applyButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -100),
            applyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            cancelButton.bottomAnchor.constraint(equalTo: applyButton.bottomAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: applyButton.leadingAnchor, constant: -8),

            resetButton.bottomAnchor.constraint(equalTo: applyButton.bottomAnchor),
            resetButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),

            infoLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            infoLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            infoLabel.heightAnchor.constraint(equalToConstant: 22),
            infoLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Mask: fill the whole view with a dark semi-transparent layer; cut a
        // hole where the selection is. Using fillRule=evenOdd is the simplest
        // way to "subtract" the selection from the mask.
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        let path = CGMutablePath()
        path.addRect(bounds)
        if !currentRect.isEmpty {
            path.addRect(currentRect)
        }
        ctx.addPath(path)
        ctx.fillPath(using: .evenOdd)

        // Selection border
        if !currentRect.isEmpty {
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(currentRect)
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        infoLabel.isHidden = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(x: min(start.x, p.x),
                             y: min(start.y, p.y),
                             width: abs(p.x - start.x),
                             height: abs(p.y - start.y))
        updateInfo()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        startPoint = nil
        updateInfo()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        // Escape cancels (matches "Escape Key Behavior" intent for the modal)
        if event.keyCode == 53 {
            cancelTapped()
        } else {
            super.keyDown(with: event)
        }
    }

    private func updateInfo() {
        guard let geo = cropGeometry() else {
            infoLabel.stringValue = L("Drag to select crop area")
            return
        }
        infoLabel.stringValue = geo
    }

    /// Translate the drag rect (in our view's points) to a libvlc crop
    /// geometry string in source pixels: "WIDTHxHEIGHT+X+Y". Accounts for
    /// letterbox: the video shown inside our bounds is fit-to-aspect inside
    /// `bounds`, so we compute the actual displayed video rect first, then
    /// map relative position into source pixels.
    func cropGeometry() -> String? {
        guard let src = videoSize(), src.width > 0, src.height > 0 else { return nil }
        guard currentRect.width > 4, currentRect.height > 4 else { return nil }

        let viewAspect = bounds.width / bounds.height
        let srcAspect = src.width / src.height

        let displayed: NSRect
        if viewAspect > srcAspect {
            // Pillarbox: bars on left/right, video uses full height
            let w = bounds.height * srcAspect
            displayed = NSRect(x: (bounds.width - w) / 2, y: 0, width: w, height: bounds.height)
        } else {
            // Letterbox: bars on top/bottom
            let h = bounds.width / srcAspect
            displayed = NSRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
        }

        // Clip selection to the actual displayed video area
        let sel = currentRect.intersection(displayed)
        guard !sel.isEmpty else { return nil }

        // Map sel from view coords (origin bottom-left) into source-pixel
        // coords (origin top-left, where libvlc & AVPlayer want them).
        let scaleX = src.width / displayed.width
        let scaleY = src.height / displayed.height
        let srcX = Int((sel.minX - displayed.minX) * scaleX)
        let srcW = Int(sel.width * scaleX)
        let srcH = Int(sel.height * scaleY)
        let srcY = Int(src.height) - Int((sel.minY - displayed.minY) * scaleY) - srcH
        // Clamp inside source bounds
        let cX = max(0, min(Int(src.width) - srcW, srcX))
        let cY = max(0, min(Int(src.height) - srcH, srcY))
        return "\(srcW)x\(srcH)+\(cX)+\(cY)"
    }

    @objc private func applyTapped() { onApply?(cropGeometry()) }
    @objc private func cancelTapped() { onApply?(nil) }
    @objc private func resetTapped() {
        currentRect = .zero
        infoLabel.isHidden = true
        needsDisplay = true
        onApply?("")  // empty string = explicit "remove crop"
    }
}
