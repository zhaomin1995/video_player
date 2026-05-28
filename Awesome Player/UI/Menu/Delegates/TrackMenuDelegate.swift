/// Dynamically populates audio/video/subtitle track menus when opened.
/// Queries the active player engine for available tracks.
import Cocoa

class TrackMenuDelegate: NSObject, NSMenuDelegate {
    enum TrackType { case audio, video, subtitle }
    let trackType: TrackType

    static let audio = TrackMenuDelegate(type: .audio)
    static let video = TrackMenuDelegate(type: .video)
    static let subtitle = TrackMenuDelegate(type: .subtitle)

    init(type: TrackType) {
        self.trackType = type
        super.init()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let wc = NSApp.mainWindow?.windowController as? PlayerWindowController else {
            addNoneItem(to: menu)
            return
        }
        let vc = wc.playerViewController

        if let vlc = vc.vlcEngine {
            populateVLCTracks(menu: menu, vlc: vlc, vc: vc)
        } else if let avEngine = vc.playerEngine {
            populateAVTracks(menu: menu, engine: avEngine, vc: vc)
        } else {
            addNoneItem(to: menu)
        }
    }

    private func populateVLCTracks(menu: NSMenu, vlc: VLCPlayerEngine, vc: PlayerViewController) {
        let tracks: [VLCPlayerEngine.TrackInfo]
        let currentId: Int

        switch trackType {
        case .audio:
            tracks = vlc.getAudioTracks()
            currentId = vlc.getCurrentAudioTrack()
        case .subtitle:
            tracks = vlc.getSubtitleTracks()
            currentId = vlc.getCurrentSubtitleTrack()
        case .video:
            tracks = vlc.getVideoTracks()
            currentId = -1
        }

        if tracks.isEmpty {
            addNoneItem(to: menu)
            return
        }

        for track in tracks {
            let item = menu.addItem(withTitle: track.name, action: #selector(trackSelected(_:)), keyEquivalent: "")
            item.tag = track.id
            item.target = self
            if track.id == currentId { item.state = .on }
        }
    }

    private func populateAVTracks(menu: NSMenu, engine: AVPlayerEngine, vc: PlayerViewController) {
        switch trackType {
        case .audio:
            let tracks = engine.getAudioTracks()
            if tracks.isEmpty { addNoneItem(to: menu); return }
            for track in tracks {
                let item = menu.addItem(withTitle: track.name, action: #selector(trackSelected(_:)), keyEquivalent: "")
                item.tag = track.index
                item.target = self
            }
        case .subtitle:
            let tracks = engine.getSubtitleTracks()
            let off = menu.addItem(withTitle: L("Off"), action: #selector(trackSelected(_:)), keyEquivalent: "")
            off.tag = -1
            off.target = self
            for track in tracks {
                let item = menu.addItem(withTitle: track.name, action: #selector(trackSelected(_:)), keyEquivalent: "")
                item.tag = track.index
                item.target = self
            }
        case .video:
            addNoneItem(to: menu)
        }
    }

    @objc private func trackSelected(_ sender: NSMenuItem) {
        guard let wc = NSApp.mainWindow?.windowController as? PlayerWindowController else { return }
        let vc = wc.playerViewController
        let trackId = sender.tag

        if let vlc = vc.vlcEngine {
            switch trackType {
            case .audio: vlc.setAudioTrack(trackId)
            case .subtitle: vlc.setSubtitleTrack(trackId)
            case .video: vlc.setVideoTrack(trackId)
            }
        } else if let engine = vc.playerEngine {
            switch trackType {
            case .audio: engine.selectAudioTrack(at: trackId)
            case .subtitle: engine.selectSubtitleTrack(at: trackId)
            case .video: break
            }
        }
        vc.showOSD(String(format: L("Track: %@"), sender.title))
    }

    private func addNoneItem(to menu: NSMenu) {
        let item = NSMenuItem(title: L("(None)"), action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }
}
