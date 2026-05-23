import Cocoa

class PlaylistPanelView: NSView {
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let searchField = NSSearchField()
    private let repeatButton = NSButton()
    private let shuffleButton = NSButton()
    private let addButton = NSButton()
    private let removeButton = NSButton()
    private let countLabel = NSTextField(labelWithString: "0 items")

    var items: [URL] = [] {
        didSet {
            tableView.reloadData()
            countLabel.stringValue = "\(items.count) items"
        }
    }
    var selectedIndex: Int = -1
    var onItemSelected: ((Int) -> Void)?
    var onAddFiles: (() -> Void)?
    var onRemoveItem: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        let titleLabel = NSTextField(labelWithString: "Playlist")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        searchField.placeholderString = "Search"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchField)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "Name"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.rowHeight = 28

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        addSubview(scrollView)

        let bottomBar = NSStackView()
        bottomBar.orientation = .horizontal
        bottomBar.spacing = 8
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        configureSmallButton(repeatButton, symbol: "repeat", action: nil)
        configureSmallButton(shuffleButton, symbol: "shuffle", action: nil)
        configureSmallButton(addButton, symbol: "plus", action: #selector(addClicked))
        configureSmallButton(removeButton, symbol: "minus", action: #selector(removeClicked))

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor

        bottomBar.addArrangedSubview(repeatButton)
        bottomBar.addArrangedSubview(shuffleButton)
        bottomBar.addArrangedSubview(NSView())
        bottomBar.addArrangedSubview(countLabel)
        bottomBar.addArrangedSubview(addButton)
        bottomBar.addArrangedSubview(removeButton)
        addSubview(bottomBar)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            searchField.topAnchor.constraint(equalTo: topAnchor),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 150),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -4),

            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    private func configureSmallButton(_ button: NSButton, symbol: String, action: Selector?) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.isBordered = false
        button.contentTintColor = .white
        if let action = action {
            button.target = self
            button.action = action
        }
    }

    @objc private func addClicked() { onAddFiles?() }
    @objc private func removeClicked() {
        let row = tableView.selectedRow
        if row >= 0 { onRemoveItem?(row) }
    }
}

extension PlaylistPanelView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: items[row].deletingPathExtension().lastPathComponent)
        cell.textColor = row == selectedIndex ? .systemBlue : .white
        cell.font = .systemFont(ofSize: 12)
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        if row >= 0 { onItemSelected?(row) }
    }
}
