import Cocoa

class CastPanelView: NSView {
    private let deviceTableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "Searching for devices…")
    private let disconnectButton = NSButton()
    private let refreshButton = NSButton()

    var devices: [CastDevice] = [] {
        didSet {
            deviceTableView.reloadData()
            statusLabel.stringValue = devices.isEmpty ? "No devices found" : "\(devices.count) device(s) found"
        }
    }

    var onDeviceSelected: ((CastDevice) -> Void)?
    var onDisconnect: (() -> Void)?
    var onRefresh: (() -> Void)?

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

        let title = NSTextField(labelWithString: "Cast")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .white
        stack.addArrangedSubview(title)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(statusLabel)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("device"))
        column.title = "Device"
        deviceTableView.addTableColumn(column)
        deviceTableView.headerView = nil
        deviceTableView.dataSource = self
        deviceTableView.delegate = self
        deviceTableView.backgroundColor = .clear
        deviceTableView.rowHeight = 32

        scrollView.documentView = deviceTableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        stack.addArrangedSubview(scrollView)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        refreshButton.title = "Refresh"
        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)

        disconnectButton.title = "Disconnect"
        disconnectButton.bezelStyle = .rounded
        disconnectButton.target = self
        disconnectButton.action = #selector(disconnectClicked)
        disconnectButton.isEnabled = false

        buttonRow.addArrangedSubview(refreshButton)
        buttonRow.addArrangedSubview(disconnectButton)
        stack.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    func setConnected(_ connected: Bool, deviceName: String? = nil) {
        disconnectButton.isEnabled = connected
        if connected, let name = deviceName {
            statusLabel.stringValue = "Connected to \(name)"
        }
    }

    @objc private func refreshClicked() { onRefresh?() }
    @objc private func disconnectClicked() { onDisconnect?() }
}

extension CastPanelView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { devices.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let device = devices[row]
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8

        let icon: String
        switch device.type {
        case .airplay: icon = "airplayvideo"
        case .chromecast: icon = "tv"
        case .dlna: icon = "display"
        }

        let img = NSImageView(image: NSImage(systemSymbolName: icon, accessibilityDescription: nil)!)
        img.contentTintColor = .white
        img.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let nameLabel = NSTextField(labelWithString: device.name)
        nameLabel.textColor = .white
        nameLabel.font = .systemFont(ofSize: 12)

        let typeLabel = NSTextField(labelWithString: "\(device.type)")
        typeLabel.textColor = .secondaryLabelColor
        typeLabel.font = .systemFont(ofSize: 10)

        stack.addArrangedSubview(img)
        stack.addArrangedSubview(nameLabel)
        stack.addArrangedSubview(typeLabel)
        return stack
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = deviceTableView.selectedRow
        guard row >= 0, row < devices.count else { return }
        onDeviceSelected?(devices[row])
    }
}
