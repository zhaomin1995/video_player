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
            // Check if device has output channels
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

        menu.addItem(withTitle: "Open File…", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
        menu.addItem(withTitle: "Open URL…", action: #selector(AppDelegate.openURL(_:)), keyEquivalent: "u")

        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
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
        menu.addItem(withTitle: "Seek Forward 5s", action: #selector(AppDelegate.seekForward5(_:)), keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)))
        menu.addItem(withTitle: "Seek Backward 5s", action: #selector(AppDelegate.seekBackward5(_:)), keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))

        menu.addItem(.separator())
        menu.addItem(withTitle: "Jump to Time…", action: #selector(AppDelegate.jumpToTime(_:)), keyEquivalent: "j")

        menu.addItem(.separator())
        let speedMenu = NSMenuItem(title: "Speed", action: nil, keyEquivalent: "")
        let speedSubmenu = NSMenu(title: "Speed")
        for speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
            speedSubmenu.addItem(withTitle: String(format: "%.2gx", speed), action: #selector(AppDelegate.setSpeed(_:)), keyEquivalent: "")
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

        // Tracks section
        let tracksHeader = NSMenuItem(title: "Tracks", action: nil, keyEquivalent: "")
        tracksHeader.isEnabled = false
        menu.addItem(tracksHeader)
        let noTrack = NSMenuItem(title: "(None)", action: nil, keyEquivalent: "")
        noTrack.isEnabled = false
        menu.addItem(noTrack)
        menu.addItem(.separator())

        // Equalizer submenu
        let eqItem = NSMenuItem(title: "Equalizer", action: nil, keyEquivalent: "")
        let eqMenu = NSMenu(title: "Equalizer")
        for preset in ["Flat", "Bass Boost", "Treble Boost", "Vocal", "Rock", "Jazz", "Classical", "Electronic"] {
            eqMenu.addItem(withTitle: preset, action: #selector(AppDelegate.setEQPreset(_:)), keyEquivalent: "")
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
        menu.addItem(withTitle: "Increase Volume", action: #selector(AppDelegate.volumeUp(_:)), keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
        menu.addItem(withTitle: "Decrease Volume", action: #selector(AppDelegate.volumeDown(_:)), keyEquivalent: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)))
        menu.addItem(withTitle: "Mute", action: #selector(AppDelegate.toggleMute(_:)), keyEquivalent: "m")

        menuItem.submenu = menu
        return menuItem
    }

    private static func createVideoMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Video", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Video")

        // Tracks section
        let tracksHeader = NSMenuItem(title: "Tracks", action: nil, keyEquivalent: "")
        tracksHeader.isEnabled = false
        menu.addItem(tracksHeader)
        let noTrack = NSMenuItem(title: "(None)", action: nil, keyEquivalent: "")
        noTrack.isEnabled = false
        menu.addItem(noTrack)
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
        for ratio in ["Default", "4:3", "16:9", "16:10", "2.35:1", "2.39:1"] {
            aspectMenu.addItem(withTitle: ratio, action: #selector(AppDelegate.setAspectRatio(_:)), keyEquivalent: "")
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

        // Tracks section
        let tracksHeader = NSMenuItem(title: "Tracks", action: nil, keyEquivalent: "")
        tracksHeader.isEnabled = false
        menu.addItem(tracksHeader)
        let noTrack = NSMenuItem(title: "(None)", action: nil, keyEquivalent: "")
        noTrack.isEnabled = false
        menu.addItem(noTrack)
        menu.addItem(.separator())

        // Display Type submenu
        let displayItem = NSMenuItem(title: "Display Type", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu(title: "Display Type")
        displayMenu.addItem(withTitle: "Bottom of Video", action: #selector(AppDelegate.setSubtitlePosition(_:)), keyEquivalent: "")
        displayMenu.addItem(withTitle: "Bottom of Screen", action: #selector(AppDelegate.setSubtitlePosition(_:)), keyEquivalent: "")
        displayMenu.addItem(withTitle: "Letterbox", action: #selector(AppDelegate.setSubtitlePosition(_:)), keyEquivalent: "")
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

        menu.addItem(withTitle: "AirPlay", action: #selector(AppDelegate.showAirPlay(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Chromecast", action: #selector(AppDelegate.showChromecast(_:)), keyEquivalent: "")
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
