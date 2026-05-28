/// "Open URL…" / yt-dlp flow extracted from AppDelegate.
///
/// Responsibilities:
///   - Prompt the user for a URL.
///   - Decide whether it's a direct media URL or a web link that needs yt-dlp.
///   - Resolve formats via yt-dlp, let the user pick a resolution, then
///     hand the resulting stream URL(s) back to the player.
///
/// The coordinator holds a weak reference to the window controller because
/// it outlives no callback chains itself — the AppDelegate owns it for the
/// app's lifetime.
import Cocoa

final class URLOpenCoordinator {
    weak var windowController: PlayerWindowController?

    init(windowController: PlayerWindowController?) {
        self.windowController = windowController
    }

    /// Open a URL passed in from an external source (URL scheme, Services
    /// menu, bookmarklet). Skips the input dialog; otherwise routes through
    /// the same direct-media-URL / yt-dlp resolution logic as `begin()`.
    func openExternalURL(_ url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let urlString = url.absoluteString
        if isDirectMediaURL(urlString) {
            windowController?.openFile(url: url)
        } else {
            resolveWithYTDLP(urlString)
        }
    }

    func begin() {
        let alert = NSAlert()
        alert.messageText = L("Open URL")
        alert.informativeText = L("Enter a media URL or YouTube/web link:")
        alert.addButton(withTitle: L("Open"))
        alert.addButton(withTitle: L("Cancel"))
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        input.placeholderString = L("https://example.com/video.mp4 or YouTube URL")
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn, !input.stringValue.isEmpty else { return }

        let urlString = input.stringValue
        if let url = URL(string: urlString), isDirectMediaURL(urlString) {
            windowController?.openFile(url: url)
        } else {
            resolveWithYTDLP(urlString)
        }
    }

    // MARK: - Helpers

    private func isDirectMediaURL(_ url: String) -> Bool {
        let mediaExts = ["mp4", "mkv", "avi", "mov", "m4v", "webm", "flv", "wmv",
                         "mpg", "mpeg", "m4a", "mp3", "flac", "ogg"]
        let lower = url.lowercased()
        return mediaExts.contains(where: { lower.hasSuffix(".\($0)") })
    }

    private func findYTDLP() -> String? {
        let bundledPath = Bundle.main.resourceURL?.appendingPathComponent("yt-dlp/yt-dlp_macos").path
        let searchPaths = [bundledPath, "/opt/homebrew/bin/yt-dlp",
                           "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"].compactMap { $0 }
        return searchPaths.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    private func runYTDLP(_ ytdlp: String, arguments: [String]) -> (stdout: String, stderr: String, exitCode: Int32)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlp)
        process.currentDirectoryURL = URL(fileURLWithPath: ytdlp).deletingLastPathComponent()
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            // Currently misclassified upstream as "yt-dlp not found" because
            // the caller only sees nil. Log the real reason (sandbox denial,
            // exec-bit missing, etc.) so the cause is recoverable from logs.
            wlog(.player, "yt-dlp process.run() failed: \(error)")
            return nil
        }

        // Read stderr off-thread so a chatty yt-dlp can't deadlock us on a
        // full pipe buffer while we wait for stdout. The DispatchGroup
        // replaces an earlier `while !errThread.isFinished` busy-wait that
        // burned a CPU loop for ~10ms post-exit.
        let group = DispatchGroup()
        var errData = Data()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        group.wait()

        return (
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }

    private struct YTDLPFormat {
        let formatID: String
        let height: Int
        let ext: String
        let hasAudio: Bool
    }

    private func resolveWithYTDLP(_ urlString: String) {
        guard let ytdlp = findYTDLP() else {
            windowController?.playerViewController.showOSD(L("yt-dlp not found"), duration: 5.0)
            return
        }
        windowController?.playerViewController.showOSD(L("Fetching formats…"), duration: 60.0)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let result = self?.runYTDLP(ytdlp, arguments: ["-j", "--no-warnings", "--no-playlist", urlString]),
                  result.exitCode == 0,
                  let jsonData = result.stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let formats = json["formats"] as? [[String: Any]] else {
                DispatchQueue.main.async {
                    self?.windowController?.playerViewController.showOSD(L("Failed to fetch video info"), duration: 5.0)
                }
                return
            }

            let title = json["title"] as? String ?? urlString

            var videoFormats: [YTDLPFormat] = []
            var seenHeights = Set<Int>()
            for fmt in formats {
                guard let fid = fmt["format_id"] as? String,
                      let height = fmt["height"] as? Int, height > 0,
                      let vc = fmt["vcodec"] as? String, vc != "none",
                      let ext = fmt["ext"] as? String else { continue }
                let hasAudio = ((fmt["acodec"] as? String) ?? "none") != "none"
                if seenHeights.contains(height) {
                    // Prefer mp4 over webm when multiple variants share a height —
                    // mp4 plays through AVPlayer (HW path), webm requires libvlc.
                    if let idx = videoFormats.firstIndex(where: { $0.height == height }) {
                        let existing = videoFormats[idx]
                        if ext == "mp4" && existing.ext != "mp4" {
                            videoFormats[idx] = YTDLPFormat(formatID: fid, height: height, ext: ext, hasAudio: hasAudio)
                        }
                    }
                } else {
                    seenHeights.insert(height)
                    videoFormats.append(YTDLPFormat(formatID: fid, height: height, ext: ext, hasAudio: hasAudio))
                }
            }
            videoFormats.sort { $0.height > $1.height }

            guard !videoFormats.isEmpty else {
                DispatchQueue.main.async {
                    self?.windowController?.playerViewController.showOSD(L("No video formats found"), duration: 5.0)
                }
                return
            }

            DispatchQueue.main.async {
                self?.windowController?.playerViewController.showOSD("")
                self?.showResolutionPicker(title: title, formats: videoFormats, ytdlp: ytdlp, urlString: urlString)
            }
        }
    }

    private func showResolutionPicker(title: String, formats: [YTDLPFormat], ytdlp: String, urlString: String) {
        let alert = NSAlert()
        alert.messageText = L("Select Resolution")
        alert.informativeText = title
        alert.addButton(withTitle: L("Play"))
        alert.addButton(withTitle: L("Cancel"))

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 28), pullsDown: false)
        for fmt in formats {
            let suffix = fmt.hasAudio ? "" : " (video+audio merge)"
            popup.addItem(withTitle: "\(fmt.height)p\(suffix)")
        }
        popup.selectItem(at: 0)
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let chosen = formats[popup.indexOfSelectedItem]
        windowController?.playerViewController.showOSD("Loading \(chosen.height)p…", duration: 60.0)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var formatSpec = chosen.formatID
            if !chosen.hasAudio {
                // Two-stream playback: yt-dlp returns one URL per stream; the
                // player opens them with libvlc's :input-slave= option.
                formatSpec = "\(chosen.formatID)+bestaudio[ext=m4a]/\(chosen.formatID)+bestaudio"
            }
            guard let result = self?.runYTDLP(ytdlp, arguments: ["--get-url", "-f", formatSpec, "--no-warnings", "--no-playlist", urlString]),
                  result.exitCode == 0 else {
                DispatchQueue.main.async {
                    self?.windowController?.playerViewController.showOSD(L("Failed to get stream URL"), duration: 5.0)
                }
                return
            }

            let urls = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").compactMap { URL(string: $0) }
            guard let videoURL = urls.first else {
                DispatchQueue.main.async {
                    self?.windowController?.playerViewController.showOSD(L("Failed to get stream URL"), duration: 5.0)
                }
                return
            }

            let audioURL = urls.count > 1 ? urls[1] : nil

            DispatchQueue.main.async {
                if audioURL != nil {
                    self?.openStreamWithVLC(videoURL: videoURL, audioURL: audioURL, title: title)
                } else {
                    self?.windowController?.openFile(url: videoURL)
                }
            }
        }
    }

    private func openStreamWithVLC(videoURL: URL, audioURL: URL?, title: String) {
        guard let vc = windowController?.playerViewController else { return }
        vc.openStream(videoURL: videoURL, audioURL: audioURL)
        windowController?.titleBarView.setTitle(title)
    }
}
