import Cocoa

enum PanelType: Int, CaseIterable {
    case playlist
    case audio
    case subtitle
    case video
    case mediaInfo
    case cast
}

class PanelContainerView: NSView {
    private var currentPanel: PanelType?
    private let effectView = NSVisualEffectView()
    private var panelViews: [PanelType: NSView] = [:]

    let playlistPanel = PlaylistPanelView()
    let audioPanel = AudioPanelView()
    let subtitlePanel = SubtitlePanelView()
    let videoPanel = VideoPanelView()
    let mediaInfoPanel = MediaInfoPanelView()
    let castPanel = CastPanelView()

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
        isHidden = true

        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        panelViews = [
            .playlist: playlistPanel,
            .audio: audioPanel,
            .subtitle: subtitlePanel,
            .video: videoPanel,
            .mediaInfo: mediaInfoPanel,
            .cast: castPanel,
        ]

        for (_, view) in panelViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isHidden = true
            effectView.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 8),
                view.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -8),
                view.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 12),
                view.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -12),
            ])
        }
    }

    func togglePanel(_ type: PanelType) {
        if currentPanel == type {
            closePanel()
        } else {
            showPanel(type)
        }
    }

    func showPanel(_ type: PanelType) {
        for (_, view) in panelViews {
            view.isHidden = true
        }
        panelViews[type]?.isHidden = false
        currentPanel = type

        if isHidden {
            isHidden = false
            alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self.animator().alphaValue = 1.0
            }
        }
    }

    func closePanel() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 0
        } completionHandler: {
            self.isHidden = true
            for (_, view) in self.panelViews {
                view.isHidden = true
            }
            self.currentPanel = nil
        }
    }

    var isOpen: Bool { currentPanel != nil }
}
