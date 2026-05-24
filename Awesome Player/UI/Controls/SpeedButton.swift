import Cocoa

class SpeedButton: NSView {
    var onSpeedChanged: ((Float) -> Void)?

    private let button = NSButton()
    private var currentSpeed: Float = 1.0

    private let speeds: [Float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0, 4.0]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        button.title = "1.0x"
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.isBordered = false
        button.contentTintColor = .white
        button.target = self
        button.action = #selector(buttonClicked)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @objc private func buttonClicked() {
        let menu = NSMenu()
        for speed in speeds {
            let item = NSMenuItem(
                title: String(format: "%.3gx", speed),
                action: #selector(speedSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = Int(speed * 100)
            if speed == currentSpeed {
                item.state = .on
            }
            menu.addItem(item)
        }

        let location = NSPoint(x: 0, y: button.frame.height)
        menu.popUp(positioning: nil, at: location, in: button)
    }

    @objc private func speedSelected(_ sender: NSMenuItem) {
        let speed = Float(sender.tag) / 100.0
        setSpeed(speed)
        onSpeedChanged?(speed)
    }

    func setSpeed(_ speed: Float) {
        currentSpeed = speed
        button.title = String(format: "%.3gx", speed)
    }
}
