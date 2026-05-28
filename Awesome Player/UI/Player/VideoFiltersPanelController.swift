import Cocoa

/// Floating panel for toggling libvlc video filters.
///
/// libvlc 3.x has no runtime add/remove for the `--video-filter` chain — it's
/// resolved when the media object is created. So this panel just writes user
/// choices into UserDefaults; `VLCPlayerEngine.open()` reads them and builds
/// the `:video-filter=...` option string at file open. The "Reopen current
/// file" button at the bottom is the apply-now shortcut, which re-runs the
/// current file through `PlayerViewController.openFile(url:)` so the new
/// chain takes effect without the user dragging the file back in.
///
/// Why only these 5 filters: sharpen / grain genuinely improve real content
/// (sharpen for soft 480p, grain to disguise compression artifacts on flat
/// digital sources). Posterize / invert / mirror are the rest of the well-
/// tested visual-effect chain — fun for screenshots, mostly. Skipped wave /
/// ripple / psychedelic / bluescreen / motiondetect since they're either
/// broken or so niche the panel becomes clutter.
final class VideoFiltersPanelController: NSWindowController {

    static let shared = VideoFiltersPanelController()

    private let sharpenToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let sharpenSlider = NSSlider()
    private let sharpenValueLabel = NSTextField(labelWithString: "")

    private let grainToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let grainSlider = NSSlider()
    private let grainValueLabel = NSTextField(labelWithString: "")

    private let posterizeToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let invertToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let mirrorToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    private let hintLabel = NSTextField(labelWithString: "")
    private let reopenButton = NSButton(title: "", target: nil, action: nil)
    private let clearAllButton = NSButton(title: "", target: nil, action: nil)

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 340),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered, defer: true)
        panel.title = L("Video Filters")
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.center()
        super.init(window: panel)
        setupContent()
        loadFromDefaults()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupContent() {
        guard let content = window?.contentView else { return }

        for cb in [sharpenToggle, grainToggle, posterizeToggle, invertToggle, mirrorToggle] {
            cb.target = self
            cb.action = #selector(toggleChanged(_:))
            cb.translatesAutoresizingMaskIntoConstraints = false
        }
        sharpenToggle.title = L("Sharpen")
        grainToggle.title = L("Film Grain")
        posterizeToggle.title = L("Posterize")
        invertToggle.title = L("Invert Colors")
        mirrorToggle.title = L("Mirror")

        configureSlider(sharpenSlider, min: 0.0, max: 2.0)
        configureSlider(grainSlider, min: 0.1, max: 4.0)
        sharpenSlider.action = #selector(sharpenChanged)
        grainSlider.action = #selector(grainChanged)
        sharpenSlider.target = self
        grainSlider.target = self

        for label in [sharpenValueLabel, grainValueLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.translatesAutoresizingMaskIntoConstraints = false
        }

        hintLabel.stringValue = L("Filter changes apply when the file is reopened.")
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.usesSingleLineMode = false
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 2
        hintLabel.preferredMaxLayoutWidth = 290

        reopenButton.title = L("Reopen Current File")
        reopenButton.bezelStyle = .rounded
        reopenButton.target = self
        reopenButton.action = #selector(reopenCurrent)
        reopenButton.translatesAutoresizingMaskIntoConstraints = false

        clearAllButton.title = L("Clear All")
        clearAllButton.bezelStyle = .rounded
        clearAllButton.target = self
        clearAllButton.action = #selector(clearAll)
        clearAllButton.translatesAutoresizingMaskIntoConstraints = false

        let subviews: [NSView] = [
            sharpenToggle, sharpenSlider, sharpenValueLabel,
            grainToggle, grainSlider, grainValueLabel,
            posterizeToggle, invertToggle, mirrorToggle,
            hintLabel, clearAllButton, reopenButton,
        ]
        subviews.forEach { content.addSubview($0) }

        // Two-column layout: left = toggle, right = slider + value (where
        // applicable). Plain vstack for the unparameterized toggles.
        NSLayoutConstraint.activate([
            sharpenToggle.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            sharpenToggle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            sharpenSlider.centerYAnchor.constraint(equalTo: sharpenToggle.centerYAnchor),
            sharpenSlider.leadingAnchor.constraint(equalTo: sharpenToggle.trailingAnchor, constant: 12),
            sharpenSlider.trailingAnchor.constraint(equalTo: sharpenValueLabel.leadingAnchor, constant: -8),
            sharpenValueLabel.centerYAnchor.constraint(equalTo: sharpenToggle.centerYAnchor),
            sharpenValueLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            sharpenValueLabel.widthAnchor.constraint(equalToConstant: 36),

            grainToggle.topAnchor.constraint(equalTo: sharpenToggle.bottomAnchor, constant: 14),
            grainToggle.leadingAnchor.constraint(equalTo: sharpenToggle.leadingAnchor),
            grainSlider.centerYAnchor.constraint(equalTo: grainToggle.centerYAnchor),
            grainSlider.leadingAnchor.constraint(equalTo: sharpenSlider.leadingAnchor),
            grainSlider.trailingAnchor.constraint(equalTo: grainValueLabel.leadingAnchor, constant: -8),
            grainValueLabel.centerYAnchor.constraint(equalTo: grainToggle.centerYAnchor),
            grainValueLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            grainValueLabel.widthAnchor.constraint(equalToConstant: 36),

            posterizeToggle.topAnchor.constraint(equalTo: grainToggle.bottomAnchor, constant: 14),
            posterizeToggle.leadingAnchor.constraint(equalTo: sharpenToggle.leadingAnchor),

            invertToggle.topAnchor.constraint(equalTo: posterizeToggle.bottomAnchor, constant: 10),
            invertToggle.leadingAnchor.constraint(equalTo: sharpenToggle.leadingAnchor),

            mirrorToggle.topAnchor.constraint(equalTo: invertToggle.bottomAnchor, constant: 10),
            mirrorToggle.leadingAnchor.constraint(equalTo: sharpenToggle.leadingAnchor),

            hintLabel.topAnchor.constraint(equalTo: mirrorToggle.bottomAnchor, constant: 20),
            hintLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            hintLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            reopenButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            reopenButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            clearAllButton.centerYAnchor.constraint(equalTo: reopenButton.centerYAnchor),
            clearAllButton.trailingAnchor.constraint(equalTo: reopenButton.leadingAnchor, constant: -8),
        ])
    }

    private func configureSlider(_ slider: NSSlider, min: Double, max: Double) {
        slider.minValue = min
        slider.maxValue = max
        slider.translatesAutoresizingMaskIntoConstraints = false
    }

    private func loadFromDefaults() {
        let ud = UserDefaults.standard
        sharpenToggle.state = ud.bool(forKey: Defaults.filterSharpen) ? .on : .off
        sharpenSlider.doubleValue = ud.double(forKey: Defaults.filterSharpenSigma)
        if sharpenSlider.doubleValue == 0 { sharpenSlider.doubleValue = 0.5 }
        grainToggle.state = ud.bool(forKey: Defaults.filterGrain) ? .on : .off
        grainSlider.doubleValue = ud.double(forKey: Defaults.filterGrainVariance)
        if grainSlider.doubleValue == 0 { grainSlider.doubleValue = 1.0 }
        posterizeToggle.state = ud.bool(forKey: Defaults.filterPosterize) ? .on : .off
        invertToggle.state = ud.bool(forKey: Defaults.filterInvert) ? .on : .off
        mirrorToggle.state = ud.bool(forKey: Defaults.filterMirror) ? .on : .off
        updateLabels()
        updateSliderEnabled()
    }

    private func updateLabels() {
        sharpenValueLabel.stringValue = String(format: "%.1f", sharpenSlider.doubleValue)
        grainValueLabel.stringValue = String(format: "%.1f", grainSlider.doubleValue)
    }

    private func updateSliderEnabled() {
        sharpenSlider.isEnabled = sharpenToggle.state == .on
        grainSlider.isEnabled = grainToggle.state == .on
    }

    @objc private func toggleChanged(_ sender: NSButton) {
        let ud = UserDefaults.standard
        let on = sender.state == .on
        switch sender {
        case sharpenToggle: ud.set(on, forKey: Defaults.filterSharpen)
        case grainToggle:   ud.set(on, forKey: Defaults.filterGrain)
        case posterizeToggle: ud.set(on, forKey: Defaults.filterPosterize)
        case invertToggle:    ud.set(on, forKey: Defaults.filterInvert)
        case mirrorToggle:    ud.set(on, forKey: Defaults.filterMirror)
        default: break
        }
        updateSliderEnabled()
    }

    @objc private func sharpenChanged() {
        UserDefaults.standard.set(sharpenSlider.doubleValue, forKey: Defaults.filterSharpenSigma)
        updateLabels()
    }

    @objc private func grainChanged() {
        UserDefaults.standard.set(grainSlider.doubleValue, forKey: Defaults.filterGrainVariance)
        updateLabels()
    }

    @objc private func clearAll() {
        let ud = UserDefaults.standard
        [Defaults.filterSharpen, Defaults.filterGrain, Defaults.filterPosterize,
         Defaults.filterInvert, Defaults.filterMirror].forEach { ud.set(false, forKey: $0) }
        loadFromDefaults()
    }

    @objc private func reopenCurrent() {
        guard let wc = NSApp.mainWindow?.windowController as? PlayerWindowController,
              let url = wc.playerViewController.currentFileURL else { return }
        wc.playerViewController.openFile(url: url)
    }

    /// Build the libvlc video-filter chain string from current UserDefaults.
    /// Returns nil when no filter is enabled. Format is colon-separated module
    /// names with `{key=value}` parameter sets for those that take them.
    static func buildFilterChainOption() -> String? {
        let ud = UserDefaults.standard
        var modules: [String] = []
        if ud.bool(forKey: Defaults.filterSharpen) {
            let sigma = ud.double(forKey: Defaults.filterSharpenSigma)
            modules.append("sharpen{sigma=\(String(format: "%.2f", sigma > 0 ? sigma : 0.5))}")
        }
        if ud.bool(forKey: Defaults.filterGrain) {
            let v = ud.double(forKey: Defaults.filterGrainVariance)
            modules.append("grain{variance=\(String(format: "%.2f", v > 0 ? v : 1.0))}")
        }
        if ud.bool(forKey: Defaults.filterPosterize) { modules.append("posterize") }
        if ud.bool(forKey: Defaults.filterInvert)    { modules.append("invert") }
        if ud.bool(forKey: Defaults.filterMirror)    { modules.append("mirror") }
        guard !modules.isEmpty else { return nil }
        return modules.joined(separator: ":")
    }
}
