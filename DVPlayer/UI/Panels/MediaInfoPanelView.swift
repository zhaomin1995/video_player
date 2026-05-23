import Cocoa

class MediaInfoPanelView: NSView {
    private let infoStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 4
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoStack)

        let title = NSTextField(labelWithString: "Media Info")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .white
        infoStack.addArrangedSubview(title)

        NSLayoutConstraint.activate([
            infoStack.topAnchor.constraint(equalTo: topAnchor),
            infoStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            infoStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            infoStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    func update(info: MediaInfo) {
        while infoStack.arrangedSubviews.count > 1 {
            infoStack.removeArrangedSubview(infoStack.arrangedSubviews.last!)
            infoStack.arrangedSubviews.last?.removeFromSuperview()
        }

        addRow("File", info.url.lastPathComponent)
        addRow("Video Codec", info.videoCodec.rawValue)
        if let size = info.videoSize {
            addRow("Resolution", "\(Int(size.width)) × \(Int(size.height))")
        }
        addRow("HDR", info.hdrType.rawValue)
        if info.isDolbyVision { addRow("Dolby Vision", "Yes") }
        if info.isDolbyAtmos { addRow("Dolby Atmos", "Yes") }
        if let audio = info.audioCodecName { addRow("Audio Codec", audio) }
        if info.duration > 0 {
            let mins = Int(info.duration) / 60
            let secs = Int(info.duration) % 60
            addRow("Duration", String(format: "%d:%02d", mins, secs))
        }
        addRow("Engine", info.isAVPlayerCompatible ? "AVPlayer" : "FFmpeg")
        addRow("AirPlay", info.isAVPlayerCompatible ? "Available" : "Unavailable")
    }

    private func addRow(_ label: String, _ value: String) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let lbl = NSTextField(labelWithString: label + ":")
        lbl.font = .systemFont(ofSize: 11, weight: .medium)
        lbl.textColor = .secondaryLabelColor
        lbl.widthAnchor.constraint(equalToConstant: 100).isActive = true

        let val = NSTextField(labelWithString: value)
        val.font = .systemFont(ofSize: 11)
        val.textColor = .white
        val.lineBreakMode = .byTruncatingTail

        row.addArrangedSubview(lbl)
        row.addArrangedSubview(val)
        infoStack.addArrangedSubview(row)
    }
}
