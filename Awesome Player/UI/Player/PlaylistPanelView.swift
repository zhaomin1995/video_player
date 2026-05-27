import Cocoa

protocol PlaylistPanelDelegate: AnyObject {
    func playlistPanel(_ panel: PlaylistPanelView, didSelectItemAt index: Int)
    func playlistPanel(_ panel: PlaylistPanelView, didRemoveItemAt index: Int)
}

class PlaylistPanelView: NSView {
    weak var delegate: PlaylistPanelDelegate?
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let headerLabel = NSTextField(labelWithString: L("Playlist"))
    private(set) var items: [URL] = []
    var currentIndex: Int = -1 {
        didSet { tableView.reloadData() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.95).cgColor

        headerLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        headerLabel.textColor = .white
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerLabel)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.title = L("File")
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(tableDoubleClicked)
        tableView.target = self
        tableView.rowHeight = 28
        tableView.style = .plain

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func setItems(_ urls: [URL]) {
        items = urls
        tableView.reloadData()
    }

    @objc private func tableDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        delegate?.playlistPanel(self, didSelectItemAt: row)
    }
}

extension PlaylistPanelView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("PlaylistCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let v = NSTableCellView()
            v.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.lineBreakMode = .byTruncatingTail
            v.addSubview(tf)
            v.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 8),
                tf.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -8),
                tf.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            ])
            return v
        }()

        let url = items[row]
        cell.textField?.stringValue = url.deletingPathExtension().lastPathComponent
        cell.textField?.textColor = row == currentIndex ? .systemBlue : .white
        cell.textField?.font = .systemFont(ofSize: 12, weight: row == currentIndex ? .semibold : .regular)
        return cell
    }
}
