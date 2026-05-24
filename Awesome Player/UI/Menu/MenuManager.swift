import Cocoa
import CoreAudio

class AudioDeviceMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = AudioDeviceMenuDelegate()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize) == noErr else { return }

        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &deviceIDs) == noErr else { return }

        // Get default output device
        var defaultDevice: AudioDeviceID = 0
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, &defaultSize, &defaultDevice)

        for deviceID in deviceIDs {
            // Filter out virtual and aggregate devices (e.g. ZoomAudioDevice, BlackHole)
            var transportType: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(deviceID, &transportAddress, 0, nil, &transportSize, &transportType) == noErr {
                if transportType == kAudioDeviceTransportTypeVirtual ||
                   transportType == kAudioDeviceTransportTypeAggregate {
                    continue
                }
            }

            // Check if device has output streams
            var streamSize: UInt32 = 0
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize) == noErr, streamSize > 0 else { continue }

            // Get device name
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameRef: CFString = "" as CFString
            guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameRef) == noErr else { continue }

            let item = NSMenuItem(title: nameRef as String, action: #selector(AppDelegate.selectOutputDevice(_:)), keyEquivalent: "")
            item.tag = Int(deviceID)
            item.target = nil
            if deviceID == defaultDevice {
                item.state = .on
            }
            menu.addItem(item)
        }

        if menu.items.isEmpty {
            let none = NSMenuItem(title: "No devices found", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
    }
}

/// Discovers AirPlay devices via Bonjour (_airplay._tcp) and lists them in the menu.
/// Clicking a device triggers the AVRoutePickerView in the control bar.
class AirPlayMenuDelegate: NSObject, NSMenuDelegate, NetServiceBrowserDelegate, NetServiceDelegate {
    static let shared = AirPlayMenuDelegate()

    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var resolvedDevices: [(name: String, host: String)] = []

    override init() {
        super.init()
        startDiscovery()
    }

    private func startDiscovery() {
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_airplay._tcp.", inDomain: "local.")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if resolvedDevices.isEmpty {
            let scanning = NSMenuItem(title: "Scanning…", action: nil, keyEquivalent: "")
            scanning.isEnabled = false
            menu.addItem(scanning)
            // Restart discovery in case it timed out
            startDiscovery()
        } else {
            for device in resolvedDevices {
                menu.addItem(withTitle: device.name, action: #selector(AppDelegate.showAirPlay(_:)), keyEquivalent: "")
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }
        resolvedDevices.removeAll { $0.name == service.name }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let name = sender.name
        let host = sender.hostName ?? sender.name
        if !resolvedDevices.contains(where: { $0.name == name }) {
            resolvedDevices.append((name: name, host: host))
        }
    }
}

/// Discovers Chromecast devices via Bonjour (_googlecast._tcp) and lists them in the menu.
/// Extracts the friendly name from the TXT record's "fn" key, falling back to
/// stripping the UUID suffix from the mDNS service name.
class ChromecastMenuDelegate: NSObject, NSMenuDelegate, NetServiceBrowserDelegate, NetServiceDelegate {
    static let shared = ChromecastMenuDelegate()

    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var resolvedDevices: [(name: String, host: String, port: Int)] = []

    override init() {
        super.init()
        startDiscovery()
    }

    private func startDiscovery() {
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_googlecast._tcp.", inDomain: "local.")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if resolvedDevices.isEmpty {
            let scanning = NSMenuItem(title: "Scanning…", action: nil, keyEquivalent: "")
            scanning.isEnabled = false
            menu.addItem(scanning)
            startDiscovery()
        } else {
            for device in resolvedDevices {
                let item = menu.addItem(withTitle: device.name, action: #selector(AppDelegate.castToChromecast(_:)), keyEquivalent: "")
                item.representedObject = device
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }
        resolvedDevices.removeAll { $0.host == service.hostName }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        var host = sender.hostName ?? sender.name
        // Strip trailing dot from mDNS hostname
        if host.hasSuffix(".") { host = String(host.dropLast()) }

        // Try to extract the IPv4 address directly from the resolved addresses
        if let addresses = sender.addresses {
            for addrData in addresses {
                addrData.withUnsafeBytes { ptr in
                    guard let sa = ptr.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return }
                    if sa.pointee.sa_family == UInt8(AF_INET) {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                            host = String(cString: hostname)
                        }
                    }
                }
            }
        }

        let friendlyName = Self.friendlyName(for: sender)
        if !resolvedDevices.contains(where: { $0.host == host }) {
            resolvedDevices.append((name: friendlyName, host: host, port: sender.port))
        }
    }

    static func friendlyName(for service: NetService) -> String {
        // Try TXT record "fn" (friendly name) key first
        if let txtData = service.txtRecordData() {
            let dict = NetService.dictionary(fromTXTRecord: txtData)
            if let fnData = dict["fn"], let fn = String(data: fnData, encoding: .utf8), !fn.isEmpty {
                return fn
            }
        }
        // Fall back to stripping UUID suffix (e.g. "S90F-2ab6a79c..." → "S90F")
        let raw = service.name
        if let dashIdx = raw.firstIndex(of: "-") {
            let suffix = raw[raw.index(after: dashIdx)...]
            if suffix.count > 20 {
                return String(raw[..<dashIdx])
            }
        }
        return raw
    }
}

/// Populates Open Recent menu from a manually managed list in UserDefaults.
class RecentDocumentsMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = RecentDocumentsMenuDelegate()
    private static let key = "AwesomePlayer_RecentFiles"
    private static let maxRecent = 10

    static func addRecentFile(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        if paths.count > maxRecent { paths = Array(paths.prefix(maxRecent)) }
        UserDefaults.standard.set(paths, forKey: key)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let paths = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        if paths.isEmpty {
            let none = NSMenuItem(title: "(No Recent Files)", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for path in paths {
                let url = URL(fileURLWithPath: path)
                let item = menu.addItem(withTitle: url.lastPathComponent, action: #selector(openRecentFile(_:)), keyEquivalent: "")
                item.representedObject = url
                item.target = self
            }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear Menu", action: #selector(clearRecent(_:)), keyEquivalent: "")
    }

    @objc private func openRecentFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let wc = NSApp.mainWindow?.windowController as? PlayerWindowController else { return }
        wc.openFile(url: url)
    }

    @objc private func clearRecent(_ sender: NSMenuItem) {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

/// Dynamically populates audio/video/subtitle track menus when opened.
/// Queries the active player engine for available tracks.
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
            let off = menu.addItem(withTitle: "Off", action: #selector(trackSelected(_:)), keyEquivalent: "")
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
        vc.showOSD("Track: \(sender.title)")
    }

    private func addNoneItem(to menu: NSMenu) {
        let item = NSMenuItem(title: "(None)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }
}

class MenuManager {
    static func setupMainMenu() {
        let mainMenu = NSMenu()

        mainMenu.addItem(createAppMenu())
        mainMenu.addItem(createFileMenu())
        mainMenu.addItem(createPlaybackMenu())
        mainMenu.addItem(createAudioMenu())
        mainMenu.addItem(createVideoMenu())
        mainMenu.addItem(createSubtitleMenu())
        mainMenu.addItem(createPlaylistMenu())
        mainMenu.addItem(createCastMenu())
        mainMenu.addItem(createWindowMenu())
        mainMenu.addItem(createHelpMenu())

        NSApplication.shared.mainMenu = mainMenu
    }

    private static func createAppMenu() -> NSMenuItem {
        let menuItem = NSMenuItem()
        let menu = NSMenu()

        menu.addItem(withTitle: "About Awesome Player", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(AppDelegate.showPreferences(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        services.submenu = servicesMenu
        NSApplication.shared.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Awesome Player", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Awesome Player", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createFileMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "File")

        menu.addItem(withTitle: "Open File…", action: #selector(AppDelegate.openFileAction(_:)), keyEquivalent: "o")
        menu.addItem(withTitle: "Open URL…", action: #selector(AppDelegate.openURL(_:)), keyEquivalent: "u")

        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.delegate = RecentDocumentsMenuDelegate.shared
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Add Subtitle File…", action: #selector(AppDelegate.addSubtitleFile(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Save Screenshot", action: #selector(AppDelegate.saveScreenshot(_:)), keyEquivalent: "s")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.close), keyEquivalent: "w")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createPlaybackMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Playback", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Playback")

        menu.addItem(withTitle: "Play / Pause", action: #selector(AppDelegate.togglePlayPause(_:)), keyEquivalent: " ")

        menu.addItem(.separator())
        let seekFwd = menu.addItem(withTitle: "Seek Forward 5s", action: #selector(AppDelegate.seekForward5(_:)), keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)))
        seekFwd.keyEquivalentModifierMask = []
        let seekBwd = menu.addItem(withTitle: "Seek Backward 5s", action: #selector(AppDelegate.seekBackward5(_:)), keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        seekBwd.keyEquivalentModifierMask = []

        menu.addItem(.separator())
        menu.addItem(withTitle: "Jump to Time…", action: #selector(AppDelegate.jumpToTime(_:)), keyEquivalent: "j")

        menu.addItem(.separator())
        let speedMenu = NSMenuItem(title: "Speed", action: nil, keyEquivalent: "")
        let speedSubmenu = NSMenu(title: "Speed")
        for speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
            let item = speedSubmenu.addItem(withTitle: String(format: "%.2gx", speed), action: #selector(AppDelegate.setSpeed(_:)), keyEquivalent: "")
            if speed == 1.0 { item.state = .on }
        }
        speedMenu.submenu = speedSubmenu
        menu.addItem(speedMenu)

        menu.addItem(.separator())
        menu.addItem(withTitle: "A-B Repeat", action: #selector(AppDelegate.toggleABRepeat(_:)), keyEquivalent: "r")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createAudioMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Audio", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Audio")

        // Tracks section (dynamically populated)
        let tracksItem = NSMenuItem(title: "Audio Track", action: nil, keyEquivalent: "")
        let tracksSubmenu = NSMenu(title: "Audio Track")
        tracksSubmenu.delegate = TrackMenuDelegate.audio
        tracksItem.submenu = tracksSubmenu
        menu.addItem(tracksItem)
        menu.addItem(.separator())

        // Equalizer submenu
        let eqItem = NSMenuItem(title: "Equalizer", action: nil, keyEquivalent: "")
        let eqMenu = NSMenu(title: "Equalizer")
        let currentEQ = UserDefaults.standard.integer(forKey: Defaults.defaultEQPreset)
        for (i, preset) in ["Flat", "Bass Boost", "Treble Boost", "Vocal", "Rock", "Jazz", "Classical", "Electronic"].enumerated() {
            let item = eqMenu.addItem(withTitle: preset, action: #selector(AppDelegate.setEQPreset(_:)), keyEquivalent: "")
            if i == currentEQ { item.state = .on }
        }
        eqItem.submenu = eqMenu
        menu.addItem(eqItem)

        // Output Device submenu
        let deviceItem = NSMenuItem(title: "Output Device", action: nil, keyEquivalent: "")
        let deviceMenu = NSMenu(title: "Output Device")
        deviceMenu.delegate = AudioDeviceMenuDelegate.shared
        deviceItem.submenu = deviceMenu
        menu.addItem(deviceItem)
        menu.addItem(.separator())

        // Sync section
        let syncHeader = NSMenuItem(title: "Sync.", action: nil, keyEquivalent: "")
        syncHeader.isEnabled = false
        menu.addItem(syncHeader)
        menu.addItem(withTitle: "Pull", action: #selector(AppDelegate.audioSyncPull(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Push", action: #selector(AppDelegate.audioSyncPush(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Revert Sync.", action: #selector(AppDelegate.audioSyncRevert(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        // Volume section
        let volUp = menu.addItem(withTitle: "Increase Volume", action: #selector(AppDelegate.volumeUp(_:)), keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
        volUp.keyEquivalentModifierMask = []
        let volDown = menu.addItem(withTitle: "Decrease Volume", action: #selector(AppDelegate.volumeDown(_:)), keyEquivalent: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)))
        volDown.keyEquivalentModifierMask = []
        menu.addItem(withTitle: "Mute", action: #selector(AppDelegate.toggleMute(_:)), keyEquivalent: "m")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createVideoMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Video", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Video")

        // Tracks section (dynamically populated)
        let tracksItem = NSMenuItem(title: "Video Track", action: nil, keyEquivalent: "")
        let tracksSubmenu = NSMenu(title: "Video Track")
        tracksSubmenu.delegate = TrackMenuDelegate.video
        tracksItem.submenu = tracksSubmenu
        menu.addItem(tracksItem)
        menu.addItem(.separator())

        // Full Screen & PiP
        menu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "\r")
        menu.addItem(withTitle: "Picture in Picture", action: #selector(AppDelegate.togglePiP(_:)), keyEquivalent: "p")
        menu.addItem(.separator())

        // Size
        let half = menu.addItem(withTitle: "Half Size", action: #selector(AppDelegate.setHalfSize(_:)), keyEquivalent: "`")
        let actual = menu.addItem(withTitle: "Actual Size", action: #selector(AppDelegate.setOriginalSize(_:)), keyEquivalent: "1")
        let double = menu.addItem(withTitle: "Double Size", action: #selector(AppDelegate.setDoubleSize(_:)), keyEquivalent: "2")
        let fit = menu.addItem(withTitle: "Fit to Screen", action: #selector(AppDelegate.fitToScreen(_:)), keyEquivalent: "4")
        menu.addItem(.separator())

        // Fill Screen & Aspect Ratio
        menu.addItem(withTitle: "Fill Screen", action: #selector(AppDelegate.fillScreen(_:)), keyEquivalent: "f")

        let aspectItem = NSMenuItem(title: "Aspect Ratio", action: nil, keyEquivalent: "")
        let aspectMenu = NSMenu(title: "Aspect Ratio")
        for (i, ratio) in ["Default", "4:3", "16:9", "16:10", "2.35:1", "2.39:1"].enumerated() {
            let item = aspectMenu.addItem(withTitle: ratio, action: #selector(AppDelegate.setAspectRatio(_:)), keyEquivalent: "")
            if i == 0 { item.state = .on }
        }
        aspectItem.submenu = aspectMenu
        menu.addItem(aspectItem)
        menu.addItem(.separator())

        // Rotate & Flip
        let rotL = menu.addItem(withTitle: "Rotate Left", action: #selector(AppDelegate.rotateLeft(_:)), keyEquivalent: "l")
        rotL.keyEquivalentModifierMask = [.shift, .command]
        let rotR = menu.addItem(withTitle: "Rotate Right", action: #selector(AppDelegate.rotateRight(_:)), keyEquivalent: "r")
        rotR.keyEquivalentModifierMask = [.shift, .command]
        let flipH = menu.addItem(withTitle: "Flip Horizontal", action: #selector(AppDelegate.flipHorizontal(_:)), keyEquivalent: "h")
        flipH.keyEquivalentModifierMask = [.shift, .command]
        let flipV = menu.addItem(withTitle: "Flip Vertical", action: #selector(AppDelegate.flipVertical(_:)), keyEquivalent: "v")
        flipV.keyEquivalentModifierMask = [.shift, .command]
        menu.addItem(withTitle: "Revert Transform", action: #selector(AppDelegate.revertTransform(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        // Filters submenu
        let filtersItem = NSMenuItem(title: "Filters", action: nil, keyEquivalent: "")
        let filtersMenu = NSMenu(title: "Filters")
        filtersMenu.addItem(withTitle: "Video Equalizer…", action: #selector(AppDelegate.showVideoEQ(_:)), keyEquivalent: "e")
        filtersItem.submenu = filtersMenu
        menu.addItem(filtersItem)
        menu.addItem(.separator())

        // Screenshot
        let ss = menu.addItem(withTitle: "Save Screenshot", action: #selector(AppDelegate.saveScreenshot(_:)), keyEquivalent: "s")
        ss.keyEquivalentModifierMask = [.option, .command]

        menuItem.submenu = menu
        return menuItem
    }

    private static func createSubtitleMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Subtitle", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Subtitle")

        // Tracks section (dynamically populated)
        let tracksItem = NSMenuItem(title: "Subtitle Track", action: nil, keyEquivalent: "")
        let tracksSubmenu = NSMenu(title: "Subtitle Track")
        tracksSubmenu.delegate = TrackMenuDelegate.subtitle
        tracksItem.submenu = tracksSubmenu
        menu.addItem(tracksItem)
        menu.addItem(.separator())

        // Display Type submenu
        let displayItem = NSMenuItem(title: "Display Type", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu(title: "Display Type")
        for (i, pos) in ["Bottom of Video", "Bottom of Screen", "Letterbox"].enumerated() {
            let item = displayMenu.addItem(withTitle: pos, action: #selector(AppDelegate.setSubtitlePosition(_:)), keyEquivalent: "")
            if i == 0 { item.state = .on }
        }
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)

        // Hide Subtitles
        let hide = menu.addItem(withTitle: "Hide Subtitles", action: #selector(AppDelegate.toggleSubtitles(_:)), keyEquivalent: "v")
        hide.keyEquivalentModifierMask = [.control]
        menu.addItem(.separator())

        // Add Subtitle File
        menu.addItem(withTitle: "Add Subtitle File…", action: #selector(AppDelegate.addSubtitleFile(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        // Sync section
        let syncHeader = NSMenuItem(title: "Sync.", action: nil, keyEquivalent: "")
        syncHeader.isEnabled = false
        menu.addItem(syncHeader)
        menu.addItem(withTitle: "Pull", action: #selector(AppDelegate.subtitleSyncPull(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Push", action: #selector(AppDelegate.subtitleSyncPush(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Revert Sync.", action: #selector(AppDelegate.subtitleSyncRevert(_:)), keyEquivalent: "")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createPlaylistMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Playlist", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Playlist")

        let showPlaylist = menu.addItem(withTitle: "Show Playlist", action: #selector(AppDelegate.togglePlaylistPanel(_:)), keyEquivalent: "p")
        showPlaylist.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Repeat Off", action: #selector(AppDelegate.setRepeatOff(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Repeat One", action: #selector(AppDelegate.setRepeatOne(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Repeat All", action: #selector(AppDelegate.setRepeatAll(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Shuffle", action: #selector(AppDelegate.toggleShuffle(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Previous", action: #selector(AppDelegate.previousTrack(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Next", action: #selector(AppDelegate.nextTrack(_:)), keyEquivalent: "")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createCastMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Cast", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Cast")

        let airplayItem = NSMenuItem(title: "AirPlay", action: nil, keyEquivalent: "")
        let airplaySubmenu = NSMenu(title: "AirPlay")
        airplaySubmenu.delegate = AirPlayMenuDelegate.shared
        airplayItem.submenu = airplaySubmenu
        menu.addItem(airplayItem)

        menu.addItem(withTitle: "Play on External Display", action: #selector(AppDelegate.playOnExternalDisplay(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        let chromecastItem = NSMenuItem(title: "Chromecast", action: nil, keyEquivalent: "")
        let chromecastSubmenu = NSMenu(title: "Chromecast")
        chromecastSubmenu.delegate = ChromecastMenuDelegate.shared
        chromecastItem.submenu = chromecastSubmenu
        menu.addItem(chromecastItem)

        menu.addItem(withTitle: "DLNA", action: #selector(AppDelegate.showDLNA(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Disconnect", action: #selector(AppDelegate.disconnectCast(_:)), keyEquivalent: "")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createWindowMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Window")

        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Keep on Top", action: #selector(AppDelegate.toggleAlwaysOnTop(_:)), keyEquivalent: "t")

        NSApplication.shared.windowsMenu = menu
        menuItem.submenu = menu
        return menuItem
    }

    private static func createHelpMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Help")
        menu.addItem(withTitle: "Awesome Player Help", action: #selector(NSApplication.showHelp(_:)), keyEquivalent: "?")
        NSApplication.shared.helpMenu = menu
        menuItem.submenu = menu
        return menuItem
    }
}
