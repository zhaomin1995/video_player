/// Convert/Stream window — VLC's File → Convert/Stream… equivalent.
/// Uses libvlc's sout (stream output) module to transcode media files via
/// the same shared libvlc instance as playback. The sout option string tells
/// libvlc to push decoded frames through a transcode block (which re-encodes
/// to the chosen codecs) and then to a standard output block (which writes
/// to a file or streams over the network).
///
/// We deliberately reuse the shared libvlc instance instead of creating a
/// dedicated one — libvlc supports multiple concurrent media players on
/// one instance, and creating a second instance would double VLC plugin
/// scan cost (~50ms).
import Cocoa
import UniformTypeIdentifiers
import Darwin
import IOKit

struct ConvertProfile {
    let name: String
    /// libvlc fourcc, e.g. "h264", "VP80", "theo", "WMV2". nil for audio-only.
    let videoCodec: String?
    /// libvlc fourcc, e.g. "mp3", "vorb", "flac", "mp4a"
    let audioCodec: String
    /// libvlc mux name, e.g. "mp4", "webm", "ts", "ogg", "asf"
    let container: String
    /// Output file extension (without dot)
    let fileExtension: String

    /// Builds the `:sout=...` option that libvlc consumes to set up the
    /// transcode + file-output chain. Format:
    ///   #transcode{vcodec=X,acodec=Y,...}:standard{access=file,mux=Z,dst=PATH}
    func soutOption(outputPath: String) -> String {
        let transcode: String
        if let v = videoCodec {
            transcode = "vcodec=\(v),acodec=\(audioCodec),ab=192,channels=2,samplerate=44100"
        } else {
            transcode = "vcodec=none,acodec=\(audioCodec),ab=192,channels=2,samplerate=44100"
        }
        return ":sout=#transcode{\(transcode)}:standard{access=file,mux=\(container),dst=\(outputPath)}"
    }
}

class ConvertStreamWindowController: NSWindowController {
    /// Mirrors VLC's built-in profile list (File → Convert/Stream → profile popup).
    static let profiles: [ConvertProfile] = [
        ConvertProfile(name: "Video - H.264 + MP3 (MP4)",      videoCodec: "h264", audioCodec: "mp3",  container: "mp4",  fileExtension: "mp4"),
        ConvertProfile(name: "Video - VP80 + Vorbis (Webm)",   videoCodec: "VP80", audioCodec: "vorb", container: "webm", fileExtension: "webm"),
        ConvertProfile(name: "Video - H.264 + MP3 (TS)",       videoCodec: "h264", audioCodec: "mp3",  container: "ts",   fileExtension: "ts"),
        ConvertProfile(name: "Video - Theora + Vorbis (OGG)",  videoCodec: "theo", audioCodec: "vorb", container: "ogg",  fileExtension: "ogv"),
        ConvertProfile(name: "Video - Theora + Flac (OGG)",    videoCodec: "theo", audioCodec: "flac", container: "ogg",  fileExtension: "ogv"),
        ConvertProfile(name: "Video - MPEG-2 + MPGA (TS)",     videoCodec: "mp2v", audioCodec: "mpga", container: "ts",   fileExtension: "ts"),
        ConvertProfile(name: "Video - WMV + WMA (ASF)",        videoCodec: "WMV2", audioCodec: "wma2", container: "asf",  fileExtension: "asf"),
        ConvertProfile(name: "Video - DIV3 + MP3 (ASF)",       videoCodec: "DIV3", audioCodec: "mp3",  container: "asf",  fileExtension: "asf"),
        ConvertProfile(name: "Audio - Vorbis (OGG)",           videoCodec: nil,    audioCodec: "vorb", container: "ogg",  fileExtension: "ogg"),
        ConvertProfile(name: "Audio - MP3",                    videoCodec: nil,    audioCodec: "mp3",  container: "raw",  fileExtension: "mp3"),
        ConvertProfile(name: "Audio - MP3 (MP4)",              videoCodec: nil,    audioCodec: "mp3",  container: "mp4",  fileExtension: "m4a"),
        ConvertProfile(name: "Audio - FLAC",                   videoCodec: nil,    audioCodec: "flac", container: "raw",  fileExtension: "flac"),
    ]

    private var selectedInputURL: URL?
    private let dropZone = ConvertDropZoneView()
    private let mediaLabel = NSTextField(labelWithString: L("No media selected"))
    private let profilePopUp = NSPopUpButton()
    private let saveButton = NSButton(title: L("Save as File"), target: nil, action: nil)
    private let streamButton = NSButton(title: L("Stream"), target: nil, action: nil)
    private let goButton = NSButton(title: L("Go!"), target: nil, action: nil)
    private let progressBar = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let usageLabel = NSTextField(labelWithString: "")

    /// libvlc handles for the in-flight conversion. nil when idle.
    private var converterPlayer: OpaquePointer?
    private var converterMedia: OpaquePointer?
    private var progressTimer: Timer?
    private var conversionStartTime: Date?
    private var pendingOutputURL: URL?

    /// Set to true by the Stream button to indicate we want network output
    /// instead of a file. Stream isn't fully implemented — the button shows
    /// a "coming soon" message because doing it right requires another UI
    /// for choosing protocol/host/port.
    private var streamMode = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("Convert & Stream")
        window.minSize = NSSize(width: 500, height: 450)
        window.center()
        super.init(window: window)
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { stopConversion(success: nil) }

    // MARK: - UI

    private func setupContent() {
        guard let contentView = window?.contentView else { return }

        // Section 1: Drop zone for media
        let dropBox = sectionBox(title: L("Drop media here"))
        dropZone.translatesAutoresizingMaskIntoConstraints = false
        dropZone.onFileDropped = { [weak self] url in self?.setInputURL(url) }
        dropBox.contentView?.addSubview(dropZone)

        mediaLabel.translatesAutoresizingMaskIntoConstraints = false
        mediaLabel.font = .systemFont(ofSize: 11)
        mediaLabel.textColor = .secondaryLabelColor
        mediaLabel.alignment = .center
        // Paths are often longer than the section box width — truncate from
        // the middle so the user still sees the parent directory (start) and
        // the filename (end) instead of either being clipped.
        mediaLabel.lineBreakMode = .byTruncatingMiddle
        mediaLabel.cell?.lineBreakMode = .byTruncatingMiddle
        mediaLabel.toolTip = nil
        dropBox.contentView?.addSubview(mediaLabel)

        let openButton = NSButton(title: L("Open Media…"), target: self, action: #selector(openMediaClicked))
        openButton.bezelStyle = .rounded
        openButton.translatesAutoresizingMaskIntoConstraints = false
        dropBox.contentView?.addSubview(openButton)

        // Section 2: Profile picker
        let profileBox = sectionBox(title: L("Choose Profile"))
        for p in Self.profiles { profilePopUp.addItem(withTitle: p.name) }
        profilePopUp.selectItem(at: 0)
        profilePopUp.translatesAutoresizingMaskIntoConstraints = false
        profileBox.contentView?.addSubview(profilePopUp)

        // Section 3: Destination
        let destBox = sectionBox(title: L("Choose Destination"))
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(saveAsFileClicked)
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        streamButton.bezelStyle = .rounded
        streamButton.target = self
        streamButton.action = #selector(streamClicked)
        streamButton.translatesAutoresizingMaskIntoConstraints = false

        let destStack = NSStackView(views: [streamButton, saveButton])
        destStack.spacing = 12
        destStack.translatesAutoresizingMaskIntoConstraints = false
        destBox.contentView?.addSubview(destStack)

        // Progress + Go button row
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.isHidden = true

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        usageLabel.translatesAutoresizingMaskIntoConstraints = false
        usageLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        usageLabel.textColor = .tertiaryLabelColor
        usageLabel.isHidden = true

        goButton.bezelStyle = .rounded
        goButton.keyEquivalent = "\r"
        goButton.target = self
        goButton.action = #selector(goClicked)
        goButton.isEnabled = false
        goButton.translatesAutoresizingMaskIntoConstraints = false

        [dropBox, profileBox, destBox, progressBar, statusLabel, usageLabel, goButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        // Layout
        NSLayoutConstraint.activate([
            dropBox.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            dropBox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            dropBox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            dropBox.heightAnchor.constraint(equalToConstant: 180),

            dropZone.topAnchor.constraint(equalTo: dropBox.contentView!.topAnchor, constant: 20),
            dropZone.centerXAnchor.constraint(equalTo: dropBox.contentView!.centerXAnchor),
            dropZone.widthAnchor.constraint(equalToConstant: 100),
            dropZone.heightAnchor.constraint(equalToConstant: 80),

            openButton.topAnchor.constraint(equalTo: dropZone.bottomAnchor, constant: 8),
            openButton.centerXAnchor.constraint(equalTo: dropBox.contentView!.centerXAnchor),

            mediaLabel.topAnchor.constraint(equalTo: openButton.bottomAnchor, constant: 8),
            mediaLabel.leadingAnchor.constraint(equalTo: dropBox.contentView!.leadingAnchor, constant: 12),
            mediaLabel.trailingAnchor.constraint(equalTo: dropBox.contentView!.trailingAnchor, constant: -12),

            profileBox.topAnchor.constraint(equalTo: dropBox.bottomAnchor, constant: 12),
            profileBox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            profileBox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            profileBox.heightAnchor.constraint(equalToConstant: 80),

            profilePopUp.centerXAnchor.constraint(equalTo: profileBox.contentView!.centerXAnchor),
            profilePopUp.centerYAnchor.constraint(equalTo: profileBox.contentView!.centerYAnchor),
            profilePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),

            destBox.topAnchor.constraint(equalTo: profileBox.bottomAnchor, constant: 12),
            destBox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            destBox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            destBox.heightAnchor.constraint(equalToConstant: 90),

            destStack.centerXAnchor.constraint(equalTo: destBox.contentView!.centerXAnchor),
            destStack.centerYAnchor.constraint(equalTo: destBox.contentView!.centerYAnchor),

            progressBar.topAnchor.constraint(equalTo: destBox.bottomAnchor, constant: 12),
            progressBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            progressBar.trailingAnchor.constraint(equalTo: goButton.leadingAnchor, constant: -12),
            progressBar.centerYAnchor.constraint(equalTo: goButton.centerYAnchor),

            statusLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: goButton.leadingAnchor, constant: -12),

            // CPU/GPU usage row sits below the Converting/ETA line during a
            // running conversion; hidden when idle.
            usageLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 2),
            usageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            usageLabel.trailingAnchor.constraint(lessThanOrEqualTo: goButton.leadingAnchor, constant: -12),
            usageLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            goButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40),
            goButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            goButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])
    }

    private func sectionBox(title: String) -> NSBox {
        let box = NSBox()
        box.title = title
        box.titleFont = .systemFont(ofSize: 13, weight: .semibold)
        box.boxType = .primary
        return box
    }

    private func setInputURL(_ url: URL) {
        selectedInputURL = url
        // Show the full file path; the label middle-truncates if it overflows
        // the section box. Also set toolTip so hovering reveals the full
        // path without truncation.
        mediaLabel.stringValue = url.path
        mediaLabel.toolTip = url.path
        mediaLabel.textColor = .labelColor
        goButton.isEnabled = true
    }

    // MARK: - Actions

    @objc private func openMediaClicked() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.setInputURL(url)
        }
    }

    @objc private func saveAsFileClicked() {
        streamMode = false
        saveButton.state = .on
        streamButton.state = .off
    }

    @objc private func streamClicked() {
        // Stream output (HTTP/RTSP/etc.) requires a separate dialog to pick
        // protocol, host, and port. For this release we don't implement it
        // and just show a notice.
        let alert = NSAlert()
        alert.messageText = L("Stream Output")
        alert.informativeText = L("Streaming is not implemented yet. Use Save as File to transcode to disk.")
        alert.runModal()
    }

    @objc private func goClicked() {
        guard let input = selectedInputURL else { return }
        let profile = Self.profiles[profilePopUp.indexOfSelectedItem]

        let savePanel = NSSavePanel()
        savePanel.title = L("Save Converted Media")
        savePanel.nameFieldStringValue = input.deletingPathExtension().lastPathComponent + "." + profile.fileExtension
        if let utType = UTType(filenameExtension: profile.fileExtension) {
            savePanel.allowedContentTypes = [utType]
        }
        savePanel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let outputURL = savePanel.url else { return }
            self?.startConversion(input: input, output: outputURL, profile: profile)
        }
    }

    // MARK: - Conversion

    private func startConversion(input: URL, output: URL, profile: ConvertProfile) {
        guard let instance = VLCPlayerEngine.sharedInstance else {
            statusLabel.stringValue = L("libvlc instance unavailable")
            return
        }

        // Bail if a previous conversion is still alive (shouldn't happen
        // because the button is disabled during conversion, but be defensive)
        if converterPlayer != nil { stopConversion(success: nil) }

        // Build the media + sout option
        guard let media = libvlc_media_new_path(instance, input.path) else {
            statusLabel.stringValue = L("Failed to open input file")
            return
        }
        let sout = profile.soutOption(outputPath: output.path)
        libvlc_media_add_option(media, sout)
        // `:no-sout-all` skips passthrough streams we didn't transcode (subs).
        // `:sout-keep` is harmless but keeps the chain alive between media.
        libvlc_media_add_option(media, ":no-sout-all")
        libvlc_media_add_option(media, ":sout-keep")
        // Run as fast as the decoder can — there's no video output to vsync to
        libvlc_media_add_option(media, ":no-audio")

        guard let player = libvlc_media_player_new_from_media(media) else {
            libvlc_media_release(media)
            statusLabel.stringValue = L("Failed to create transcoder")
            return
        }
        // Do NOT call libvlc_media_player_set_nsobject — convert is headless.
        libvlc_media_player_play(player)

        converterMedia = media
        converterPlayer = player
        pendingOutputURL = output
        conversionStartTime = Date()

        // UI: enter "converting" state
        goButton.isEnabled = false
        saveButton.isEnabled = false
        streamButton.isEnabled = false
        profilePopUp.isEnabled = false
        progressBar.isHidden = false
        progressBar.doubleValue = 0
        statusLabel.stringValue = L("Converting…")
        usageLabel.isHidden = false
        usageLabel.stringValue = ""

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tickProgress()
        }
    }

    private func tickProgress() {
        guard let player = converterPlayer else { return }
        let state = libvlc_media_player_get_state(player)
        switch state {
        case libvlc_Ended:
            stopConversion(success: true)
        case libvlc_Error:
            stopConversion(success: false)
        default:
            let pos = Double(libvlc_media_player_get_position(player))
            progressBar.doubleValue = pos
            if let start = conversionStartTime, pos > 0.01 {
                let elapsed = Date().timeIntervalSince(start)
                let eta = elapsed / pos - elapsed
                statusLabel.stringValue = String(format: L("Converting %.0f%%  •  ETA %.0fs"), pos * 100, eta)
            }
            updateUsageLabel()
        }
    }

    private func updateUsageLabel() {
        let cpu = SystemUsageSampler.currentProcessCPUPercent()
        let cpuText = String(format: L("CPU %.0f%%"), cpu)
        if let gpu = SystemUsageSampler.currentGPUPercent() {
            usageLabel.stringValue = "\(cpuText)  •  " + String(format: L("GPU %.0f%%"), gpu)
        } else {
            // No IOAccelerator service exposed a utilization figure — still
            // show CPU, just omit the GPU half rather than printing N/A.
            usageLabel.stringValue = cpuText
        }
    }

    private func stopConversion(success: Bool?) {
        progressTimer?.invalidate()
        progressTimer = nil

        if let player = converterPlayer {
            libvlc_media_player_stop(player)
            libvlc_media_player_release(player)
        }
        if let media = converterMedia {
            libvlc_media_release(media)
        }
        converterPlayer = nil
        converterMedia = nil

        // Re-enable controls
        goButton.isEnabled = selectedInputURL != nil
        saveButton.isEnabled = true
        streamButton.isEnabled = true
        profilePopUp.isEnabled = true

        guard let success = success else {
            // Called from deinit — just clean up, no UI updates
            return
        }

        progressBar.isHidden = true
        usageLabel.isHidden = true
        if success, let out = pendingOutputURL {
            statusLabel.stringValue = "Saved to \(out.lastPathComponent)"
            let alert = NSAlert()
            alert.messageText = L("Conversion Complete")
            alert.informativeText = "Saved to \(out.path)"
            alert.addButton(withTitle: L("Reveal in Finder"))
            alert.addButton(withTitle: L("OK"))
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([out])
            }
        } else {
            statusLabel.stringValue = L("Conversion failed")
            let alert = NSAlert()
            alert.messageText = L("Conversion Failed")
            alert.informativeText = L("libvlc reported an error during transcoding. The profile may be incompatible with the source codec.")
            alert.runModal()
        }
        pendingOutputURL = nil
        conversionStartTime = nil
    }
}

/// Drop target shown at the top of the Convert window. Mirrors VLC's
/// "Drop media here" affordance with a dashed border + downward arrow icon.
class ConvertDropZoneView: NSView {
    var onFileDropped: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
        path.lineWidth = 1.5
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.tertiaryLabelColor.setStroke()
        path.stroke()

        let arrow = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 36, weight: .light))
        arrow?.draw(in: NSRect(x: bounds.midX - 20, y: bounds.midY - 20, width: 40, height: 40))
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let url = urls.first else { return false }
        onFileDropped?(url)
        return true
    }
}

// MARK: - System Usage Sampler

/// Samples our process's CPU usage and the system's GPU usage. Used by the
/// Convert/Stream window to show what the running transcode is costing.
///
/// CPU: walks our process's threads via `task_threads()` + `thread_info()`
/// and sums their `cpu_usage` field. This is what `top` reports under the
/// "%CPU" column for a process — total time spent on the CPU since the last
/// sample, normalized to per-second. Divided by core count so 100% means
/// "saturating all cores" instead of "saturating one core".
///
/// GPU: walks the IORegistry for "IOAccelerator"-class services (this is
/// what Activity Monitor's "GPU History" uses too — fully public IOKit API,
/// no private SPI). Reads the service's `PerformanceStatistics` dictionary,
/// which on both Intel and Apple Silicon Macs contains a "Device Utilization
/// %" field that's the GPU's overall busy time. Several IOAccelerator
/// services may exist (one per GPU on multi-GPU systems); we report the max.
final class SystemUsageSampler {
    /// Returns 0.0–100.0+ for the current process. 100% = one core saturated;
    /// values > 100% are possible on multi-threaded workloads.
    static func currentProcessCPUPercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        let r = task_threads(mach_task_self_, &threadList, &threadCount)
        guard r == KERN_SUCCESS, let threadList else { return 0 }

        defer {
            let size = MemoryLayout<thread_t>.stride * Int(threadCount)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)), vm_size_t(size))
        }

        // THREAD_BASIC_INFO_COUNT isn't bridged to Swift; compute it
        // from the struct size (it's the count of natural_t words).
        let basicInfoCount = mach_msg_type_number_t(
            MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )

        var total: Double = 0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = basicInfoCount
            let infoResult = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                    thread_info(threadList[i], thread_flavor_t(THREAD_BASIC_INFO), ptr, &count)
                }
            }
            guard infoResult == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 else { continue }
            // cpu_usage is in 1/1000 of TH_USAGE_SCALE
            total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
        }
        return total
    }

    /// Returns 0.0–100.0 for the busiest GPU in the system, or nil if no
    /// IOAccelerator service was found (rare — would mean no GPU at all).
    static func currentGPUPercent() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                            IOServiceMatching("IOAccelerator"),
                                            &iter) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iter) }

        var maxUtil: Double = -1
        while case let service = IOIteratorNext(iter), service != 0 {
            defer { IOObjectRelease(service) }
            var unmanagedProps: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanagedProps, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = unmanagedProps?.takeRetainedValue() as? [String: Any],
                  let perf = props["PerformanceStatistics"] as? [String: Any] else { continue }

            // Apple Silicon: "Device Utilization %"
            // Intel: same key on most discrete + integrated GPUs
            // Fallback: "GPU Activity(%)" on some older Intel drivers
            let candidates = ["Device Utilization %", "GPU Activity(%)", "GPU Utilization %"]
            for key in candidates {
                if let v = perf[key] as? Int {
                    maxUtil = max(maxUtil, Double(v))
                    break
                } else if let v = perf[key] as? Double {
                    maxUtil = max(maxUtil, v)
                    break
                }
            }
        }
        return maxUtil >= 0 ? maxUtil : nil
    }
}
