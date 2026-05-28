/// "Search OpenSubtitles…" modal window.
///
/// Two-stage flow:
///   1. Query field + Search button — hits OpenSubtitlesService.search.
///   2. Results table — double-click or Download button triggers download
///      and hands the saved file back via the onDownloaded callback.
///
/// Credentials check happens lazily on Search; if missing, we surface an
/// actionable alert pointing at Preferences. The window itself owns no
/// credentials UI to keep concerns separated.
import Cocoa

final class OpenSubtitlesSearchWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onDownloaded: ((URL) -> Void)?

    private let queryField = NSTextField(string: "")
    private let languageField = NSTextField(string: "en")
    private let searchButton = NSButton(title: L("Search"), target: nil, action: nil)
    private let downloadButton = NSButton(title: L("Download & Load"), target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private let scrollView = NSScrollView()
    private var results: [OpenSubtitlesService.SubtitleResult] = []

    init(initialQuery: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("Search OpenSubtitles")
        window.minSize = NSSize(width: 480, height: 360)
        window.center()
        super.init(window: window)
        queryField.stringValue = initialQuery
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupContent() {
        guard let contentView = window?.contentView else { return }

        queryField.placeholderString = L("Movie or show title")
        queryField.translatesAutoresizingMaskIntoConstraints = false
        languageField.placeholderString = "en"
        languageField.translatesAutoresizingMaskIntoConstraints = false
        languageField.toolTip = L("Comma-separated ISO codes, e.g. en,zh,ja")

        searchButton.bezelStyle = .rounded
        searchButton.target = self
        searchButton.action = #selector(searchClicked)
        searchButton.keyEquivalent = "\r"
        searchButton.translatesAutoresizingMaskIntoConstraints = false

        downloadButton.bezelStyle = .rounded
        downloadButton.target = self
        downloadButton.action = #selector(downloadClicked)
        downloadButton.isEnabled = false
        downloadButton.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // Table: language | release | downloads
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = false
        table.target = self
        table.doubleAction = #selector(downloadClicked)
        let col1 = NSTableColumn(identifier: .init("lang"))
        col1.title = L("Lang")
        col1.width = 60
        let col2 = NSTableColumn(identifier: .init("release"))
        col2.title = L("Release")
        col2.width = 380
        let col3 = NSTableColumn(identifier: .init("downloads"))
        col3.title = L("Downloads")
        col3.width = 90
        table.addTableColumn(col1)
        table.addTableColumn(col2)
        table.addTableColumn(col3)
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .lineBorder

        [queryField, languageField, searchButton, downloadButton, statusLabel, scrollView].forEach {
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            queryField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            queryField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            queryField.widthAnchor.constraint(equalToConstant: 360),

            languageField.centerYAnchor.constraint(equalTo: queryField.centerYAnchor),
            languageField.leadingAnchor.constraint(equalTo: queryField.trailingAnchor, constant: 8),
            languageField.widthAnchor.constraint(equalToConstant: 100),

            searchButton.centerYAnchor.constraint(equalTo: queryField.centerYAnchor),
            searchButton.leadingAnchor.constraint(equalTo: languageField.trailingAnchor, constant: 8),

            scrollView.topAnchor.constraint(equalTo: queryField.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: downloadButton.topAnchor, constant: -12),

            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusLabel.centerYAnchor.constraint(equalTo: downloadButton.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: downloadButton.leadingAnchor, constant: -12),

            downloadButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            downloadButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    @objc private func searchClicked() {
        let q = queryField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        let langs = languageField.stringValue.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        statusLabel.stringValue = L("Searching…")
        searchButton.isEnabled = false
        downloadButton.isEnabled = false
        OpenSubtitlesService.search(query: q, languages: langs.isEmpty ? ["en"] : langs) { [weak self] result in
            DispatchQueue.main.async {
                self?.searchButton.isEnabled = true
                switch result {
                case .success(let items):
                    self?.results = items
                    self?.table.reloadData()
                    self?.statusLabel.stringValue = String(format: L("%d results"), items.count)
                case .failure(let err):
                    self?.statusLabel.stringValue = err.localizedDescription
                    self?.results = []
                    self?.table.reloadData()
                }
            }
        }
    }

    @objc private func downloadClicked() {
        let row = table.selectedRow
        guard row >= 0, row < results.count else { return }
        let chosen = results[row]
        statusLabel.stringValue = L("Downloading…")
        downloadButton.isEnabled = false
        OpenSubtitlesService.download(fileID: chosen.fileID) { [weak self] result in
            DispatchQueue.main.async {
                self?.downloadButton.isEnabled = true
                switch result {
                case .success(let url):
                    self?.statusLabel.stringValue = L("Loaded.")
                    self?.onDownloaded?(url)
                    self?.window?.close()
                case .failure(let err):
                    self?.statusLabel.stringValue = err.localizedDescription
                }
            }
        }
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = results[row]
        let cell = NSTextField(labelWithString: "")
        switch tableColumn?.identifier.rawValue {
        case "lang":      cell.stringValue = r.language
        case "release":   cell.stringValue = r.release
        case "downloads": cell.stringValue = String(r.downloadCount)
        default:          cell.stringValue = ""
        }
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        downloadButton.isEnabled = table.selectedRow >= 0
    }
}
