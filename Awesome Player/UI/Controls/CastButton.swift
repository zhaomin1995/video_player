import Cocoa
import AVKit

class CastButton: NSView {
    private var routePickerView: AVRoutePickerView?
    private var overlay: ClickInterceptView?
    var onAirPlayFallback: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
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
    }

    func showPicker() {
        for subview in routePickerView?.subviews ?? [] {
            if let button = subview as? NSButton {
                button.performClick(nil)
                return
            }
        }
    }

    func setPlayer(_ player: AVPlayer?) {
        routePickerView?.player = player
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            overlay?.removeFromSuperview()
            overlay = nil
        } else {
            if overlay == nil {
                let o = ClickInterceptView(frame: bounds)
                o.autoresizingMask = [.width, .height]
                o.onClicked = { [weak self] in
                    self?.onAirPlayFallback?()
                }
                addSubview(o)
                overlay = o
            }
        }
        toolTip = enabled ? "AirPlay / Cast" : "AirPlay"
    }
}

private class ClickInterceptView: NSView {
    var onClicked: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClicked?()
    }
}
