import Cocoa

class SubtitlePanelView: NSView {
    private let trackPopup = NSPopUpButton()
    private let delaySlider = NSSlider()
    private let delayLabel = NSTextField(labelWithString: "0.0s")
    private let encodingPopup = NSPopUpButton()
    private let fontPopup = NSPopUpButton()
    private let sizeSlider = NSSlider()
    private let addButton = NSButton()

    var onTrackChanged: ((Int) -> Void)?
    var onDelayChanged: ((Double) -> Void)?
    var onAddFile: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let title = NSTextField(labelWithString: "Subtitles")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .white
        stack.addArrangedSubview(title)

        // Track selection
        let trackRow = makeRow("Track:", trackPopup)
        trackPopup.addItem(withTitle: "None")
        trackPopup.target = self
        trackPopup.action = #selector(trackChanged)
        stack.addArrangedSubview(trackRow)

        // Add file
        addButton.title = "Add Subtitle File…"
        addButton.bezelStyle = .rounded
        addButton.target = self
        addButton.action = #selector(addClicked)
        stack.addArrangedSubview(addButton)

        // Delay
        let delayRow = NSStackView()
        delayRow.orientation = .horizontal
        let delayLbl = NSTextField(labelWithString: "Delay:")
        delayLbl.textColor = .white
        delayLbl.font = .systemFont(ofSize: 11)
        delayLbl.widthAnchor.constraint(equalToConstant: 80).isActive = true
        delaySlider.minValue = -5
        delaySlider.maxValue = 5
        delaySlider.doubleValue = 0
        delaySlider.isContinuous = true
        delaySlider.target = self
        delaySlider.action = #selector(delayChanged)
        delayLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        delayLabel.textColor = .white
        delayLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        delayRow.addArrangedSubview(delayLbl)
        delayRow.addArrangedSubview(delaySlider)
        delayRow.addArrangedSubview(delayLabel)
        stack.addArrangedSubview(delayRow)

        // Encoding
        let encRow = makeRow("Encoding:", encodingPopup)
        encodingPopup.addItems(withTitles: ["UTF-8", "GBK", "Shift-JIS", "EUC-KR", "ISO-8859-1", "Windows-1252"])
        stack.addArrangedSubview(encRow)

        // Font size
        let sizeRow = NSStackView()
        sizeRow.orientation = .horizontal
        let sizeLbl = NSTextField(labelWithString: "Size:")
        sizeLbl.textColor = .white
        sizeLbl.font = .systemFont(ofSize: 11)
        sizeLbl.widthAnchor.constraint(equalToConstant: 80).isActive = true
        sizeSlider.minValue = 12
        sizeSlider.maxValue = 48
        sizeSlider.doubleValue = 24
        sizeSlider.isContinuous = true
        sizeRow.addArrangedSubview(sizeLbl)
        sizeRow.addArrangedSubview(sizeSlider)
        stack.addArrangedSubview(sizeRow)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    private func makeRow(_ label: String, _ control: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        let lbl = NSTextField(labelWithString: label)
        lbl.textColor = .white
        lbl.font = .systemFont(ofSize: 11)
        lbl.widthAnchor.constraint(equalToConstant: 80).isActive = true
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(control)
        return row
    }

    @objc private func trackChanged() { onTrackChanged?(trackPopup.indexOfSelectedItem) }
    @objc private func delayChanged() {
        let delay = delaySlider.doubleValue
        delayLabel.stringValue = String(format: "%.1fs", delay)
        onDelayChanged?(delay)
    }
    @objc private func addClicked() { onAddFile?() }

    func setTracks(_ names: [String]) {
        trackPopup.removeAllItems()
        trackPopup.addItem(withTitle: "None")
        trackPopup.addItems(withTitles: names)
    }
}
