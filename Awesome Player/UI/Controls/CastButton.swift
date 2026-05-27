/// AirPlay/cast button with two interchangeable modes.
///
/// - .avkitPicker: shows `AVRoutePickerView`, which surfaces Apple's standard
///   AirPlay picker UI when clicked. Used for native MP4 / non-DV files where
///   AVKit's AirPlay path works. AVPlayer is attached for route routing.
///
/// - .customHandler: shows a plain `NSButton` that calls `onAirPlayFallback`
///   on click. Used for Dolby Vision files (we transcode + push via libvlc)
///   and for files already running on the libvlc engine. We need this because
///   `AVRoutePickerView`'s underlying button intercepts mouseDown via private
///   tracking — a sibling overlay view doesn't reliably catch clicks. Fully
///   replacing the picker is the only reliable way to route the click to our
///   own handler.
import Cocoa
import AVKit

class CastButton: NSView {
    enum Mode {
        case avkitPicker
        case customHandler
    }

    private var routePickerView: AVRoutePickerView?
    private var customButton: NSButton?
    private var currentMode: Mode = .avkitPicker
    private var pendingPlayer: AVPlayer?

    /// Called when the user clicks the button while in `.customHandler` mode.
    var onAirPlayFallback: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installAVKitPicker()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installAVKitPicker()
    }

    func setMode(_ mode: Mode) {
        guard mode != currentMode else { return }
        currentMode = mode
        // Tear down whichever view is currently installed
        routePickerView?.removeFromSuperview()
        routePickerView = nil
        customButton?.removeFromSuperview()
        customButton = nil
        switch mode {
        case .avkitPicker:
            installAVKitPicker()
            // Re-attach the cached AVPlayer (route picker needs it to route)
            routePickerView?.player = pendingPlayer
        case .customHandler:
            installCustomButton()
        }
    }

    func setPlayer(_ player: AVPlayer?) {
        pendingPlayer = player
        routePickerView?.player = player
    }

    /// Programmatically open the AVKit picker (only meaningful in .avkitPicker mode).
    func showPicker() {
        guard let picker = routePickerView else { return }
        for subview in picker.subviews {
            if let button = subview as? NSButton {
                button.performClick(nil)
                return
            }
        }
    }

    // MARK: - View construction

    private func installAVKitPicker() {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.setRoutePickerButtonColor(.white, for: .normal)
        picker.setRoutePickerButtonColor(.systemBlue, for: .active)
        addSubview(picker)
        routePickerView = picker
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: topAnchor),
            picker.bottomAnchor.constraint(equalTo: bottomAnchor),
            picker.leadingAnchor.constraint(equalTo: leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: trailingAnchor),
            picker.widthAnchor.constraint(equalToConstant: 28),
            picker.heightAnchor.constraint(equalToConstant: 28),
        ])
        toolTip = L("AirPlay / Cast")
    }

    private func installCustomButton() {
        let btn = NSButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isBordered = false
        btn.bezelStyle = .regularSquare
        btn.imagePosition = .imageOnly
        btn.target = self
        btn.action = #selector(customButtonClicked(_:))
        // SF Symbol matches AVKit picker's look closely
        if let img = NSImage(systemSymbolName: "airplayvideo", accessibilityDescription: "AirPlay") {
            btn.image = img
            btn.contentTintColor = .white
        } else {
            btn.title = L("AirPlay")
        }
        addSubview(btn)
        customButton = btn
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: topAnchor),
            btn.bottomAnchor.constraint(equalTo: bottomAnchor),
            btn.leadingAnchor.constraint(equalTo: leadingAnchor),
            btn.trailingAnchor.constraint(equalTo: trailingAnchor),
            btn.widthAnchor.constraint(equalToConstant: 28),
            btn.heightAnchor.constraint(equalToConstant: 28),
        ])
        toolTip = L("AirPlay")
    }

    @objc private func customButtonClicked(_ sender: NSButton) {
        onAirPlayFallback?()
    }
}
