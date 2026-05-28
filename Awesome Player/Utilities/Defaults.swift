import Foundation

enum Defaults {
    // MARK: - General
    static let theme = "general.theme" // "system", "dark", "light"
    static let transparentTitleBar = "general.transparentTitleBar"
    static let resumePlayback = "general.resumePlayback"
    static let quitOnLastWindowClosed = "general.quitOnLastWindowClosed"
    static let restoreWindowPosition = "general.restoreWindowPosition"

    // MARK: - Media Open
    static let defaultEngine = "mediaOpen.defaultEngine" // "auto", "avplayer", "ffmpeg"
    static let autoFindSeriesFiles = "mediaOpen.autoFindSeriesFiles"
    static let autoLoadSubtitles = "mediaOpen.autoLoadSubtitles"
    static let autoLoadNextFile = "mediaOpen.autoLoadNextFile"
    static let openInNewWindow = "mediaOpen.openInNewWindow"
    static let subtitleSearchScope = "mediaOpen.subtitleSearchScope"

    // MARK: - Playback
    static let defaultSpeed = "playback.defaultSpeed"
    static let shortSeekInterval = "playback.shortSeekInterval"
    static let longSeekInterval = "playback.longSeekInterval"
    static let keyFrameSeeking = "playback.keyFrameSeeking"
    static let autoPlayOnOpen = "playback.autoPlayOnOpen"
    static let mediaEndAction = "playback.mediaEndAction" // "nothing", "close", "next", "loop"
    static let abLoopGap = "playback.abLoopGap"

    // MARK: - Playlist
    static let repeatMode = "playlist.repeatMode" // "off", "one", "all"
    static let shuffle = "playlist.shuffle"
    static let playlistEndAction = "playlist.endAction"
    static let autoAddFromDirectory = "playlist.autoAddFromDirectory"
    static let sortOrder = "playlist.sortOrder"

    // MARK: - Video
    static let defaultAspectRatio = "video.defaultAspectRatio"
    static let defaultVideoSize = "video.defaultVideoSize"
    static let screenshotFormat = "video.screenshotFormat"
    static let screenshotSavePath = "video.screenshotSavePath"
    static let hdrToneMappingMode = "video.hdrToneMappingMode"
    static let fillScreenMode = "video.fillScreenMode"
    static let defaultBrightness = "video.defaultBrightness"
    static let defaultContrast = "video.defaultContrast"
    static let defaultSaturation = "video.defaultSaturation"
    static let videoDecodeMode = "video.decodeMode"       // 0=Auto, 1=HW force, 2=SW force
    static let userDefaultWidth = "video.userDefaultWidth"  // 0 = use video native
    static let smartZoomPercent = "video.smartZoomPercent"  // 100 = no upscale; 150-400 = upscale floor
    static let convertHardwareEncoding = "convert.useHardwareEncoder" // VideoToolbox encoder via venc=avcodec{codec=h264_videotoolbox}

    // MARK: - Audio
    static let defaultVolume = "audio.defaultVolume"
    static let extendedVolume = "audio.extendedVolume"
    static let passthroughMode = "audio.passthroughMode" // "auto", "on", "off"
    static let defaultEQPreset = "audio.defaultEQPreset"
    static let normalizationTarget = "audio.normalizationTarget"
    static let compressorEnabled = "audio.compressorEnabled"
    static let spatializerEnabled = "audio.spatializerEnabled"
    static let stereoWidth = "audio.stereoWidth"
    static let normalizationEnabled = "audio.normalizationEnabled"
    static let audioDelayStep = "audio.delayStep"

    // MARK: - Subtitle
    static let subtitleLanguage = "subtitle.language"
    static let autoLoadEmbedded = "subtitle.autoLoadEmbedded"
    static let autoLoadExternal = "subtitle.autoLoadExternal"
    static let defaultEncoding = "subtitle.defaultEncoding"
    static let subtitleFont = "subtitle.font"
    static let subtitleFontSize = "subtitle.fontSize"
    static let subtitleColor = "subtitle.color"
    static let subtitlePosition = "subtitle.position"
    static let subtitleOutline = "subtitle.outline"
    static let subtitleOutlineThickness = "subtitle.outlineThickness"
    static let subtitleBackgroundColor = "subtitle.backgroundColor"
    static let subtitleBackgroundOpacity = "subtitle.backgroundOpacity"
    static let subtitleDelayStep = "subtitle.delayStep"

    // MARK: - Full Screen
    static let autoEnterFullscreen = "fullscreen.autoEnter"
    static let pauseOnExitFullscreen = "fullscreen.pauseOnExit"
    static let playOnEnterFullscreen = "fullscreen.playOnEnter"
    static let blackOutOtherScreens = "fullscreen.blackOutOthers"
    static let fullscreenControlBar = "fullscreen.controlBarBehavior"
    static let timeOSDPosition = "fullscreen.timeOSDPosition"

    // MARK: - Video Filters (libvlc chain)
    static let filterSharpen = "filter.sharpen"
    static let filterSharpenSigma = "filter.sharpenSigma"
    static let filterGrain = "filter.grain"
    static let filterGrainVariance = "filter.grainVariance"
    static let filterPosterize = "filter.posterize"
    static let filterInvert = "filter.invert"
    static let filterMirror = "filter.mirror"

    // MARK: - System Awake
    static let preventSleepWhilePlaying = "system.preventSleep"
    static let allowScreenSaverForAudio = "system.allowScreenSaverForAudio"

    // MARK: - Keyboard
    static let mediaKeyEnabled = "keyboard.mediaKeyEnabled"
    static let escapeKeyBehavior = "keyboard.escapeKeyBehavior"

    // MARK: - Keyboard Shortcuts
    static let customShortcuts = "keyboard.customShortcuts"

    // MARK: - Mouse
    static let singleClickAction = "mouse.singleClickAction"
    static let doubleClickAction = "mouse.doubleClickAction"
    static let middleClickAction = "mouse.middleClickAction"
    static let scrollWheelAction = "mouse.scrollWheelAction"
    static let scrollWheelSensitivity = "mouse.scrollWheelSensitivity"
    static let rightClickAction = "mouse.rightClickAction"
    static let pinchGestureAction = "mouse.pinchGestureAction"

    // MARK: - Cast
    static let castDefaultBehavior = "cast.defaultBehavior"
    static let chromecastQuality = "cast.chromecastQuality"
    static let dlnaQuality = "cast.dlnaQuality"
    static let autoDisconnectOnClose = "cast.autoDisconnectOnClose"
    static let resumeLocalOnDisconnect = "cast.resumeLocalOnDisconnect"
    static let airplayButtonVisibility = "cast.airplayButtonVisibility"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            theme: 0,                    // 0=System, 1=Dark, 2=Light
            transparentTitleBar: true,
            resumePlayback: true,
            quitOnLastWindowClosed: true,
            restoreWindowPosition: true,
            defaultEngine: 0,            // 0=Auto, 1=AVPlayer, 2=FFmpeg
            autoFindSeriesFiles: false,
            autoLoadSubtitles: true,
            autoLoadNextFile: false,
            openInNewWindow: false,
            subtitleSearchScope: 0,      // 0=Same dir only, 1=Include subdirs
            autoPlayOnOpen: true,
            defaultSpeed: 1.0,
            shortSeekInterval: 5.0,
            longSeekInterval: 30.0,
            keyFrameSeeking: false,
            mediaEndAction: 0,           // 0=Nothing, 1=Close, 2=Next, 3=Loop
            abLoopGap: 0.0,
            repeatMode: 0,               // 0=Off, 1=One, 2=All
            shuffle: false,
            playlistEndAction: 0,        // 0=Nothing, 1=Close Window, 2=Quit
            autoAddFromDirectory: false,
            sortOrder: 0,                // 0=Name asc, 1=Name desc, 2=Date, 3=Size
            defaultAspectRatio: 0,       // 0=Auto, 1=4:3, ...
            defaultVideoSize: 0,         // 0=Fit, 1=Original, ...
            fillScreenMode: 0,           // 0=Stretch, 1=Crop
            hdrToneMappingMode: 0,       // 0=System, 1=Always HDR, 2=Force SDR
            defaultBrightness: 0.0,
            defaultContrast: 1.0,
            defaultSaturation: 1.0,
            videoDecodeMode: 0,           // 0=Auto (default — let libvlc/AVPlayer pick), 1=Force HW, 2=Force SW
            userDefaultWidth: 0,          // 0 = follow video native size; otherwise force this width in pt
            smartZoomPercent: 100,        // 100 = no upscale; 150-400 = upscale floor for small videos
            screenshotFormat: 0,         // 0=PNG, 1=JPEG, 2=TIFF
            screenshotSavePath: 0,       // 0=Desktop, 1=Pictures, 2=Downloads, 3=Custom
            defaultVolume: 1.0,
            extendedVolume: false,
            passthroughMode: 0,          // 0=Auto, 1=Always On, 2=Off
            defaultEQPreset: 0,
            compressorEnabled: false,
            spatializerEnabled: false,
            stereoWidth: 100.0,
            normalizationEnabled: false,
            normalizationTarget: -14.0,
            audioDelayStep: 100.0,
            autoLoadEmbedded: true,
            autoLoadExternal: true,
            subtitleLanguage: 0,         // 0=Any, 1=English, ...
            defaultEncoding: 0,          // 0=UTF-8, 1=Auto-detect, ...
            subtitleFont: 0,             // 0=System Default, ...
            subtitleFontSize: 24.0,
            subtitleColor: 3,            // HTML named-color index: 3 = White (see SubtitleOverlayView.namedColors)
            subtitleOutline: 0,          // 0=Black outline, ...
            subtitleOutlineThickness: 2, // pixels (0=none, max ~6)
            subtitleBackgroundColor: 0,  // HTML named-color index: 0 = Black
            subtitleBackgroundOpacity: 0.0, // 0.0 = transparent, 1.0 = solid
            subtitlePosition: 0,         // 0=Bottom of Video, ...
            subtitleDelayStep: 0.1,
            autoEnterFullscreen: false,
            pauseOnExitFullscreen: false,
            playOnEnterFullscreen: false,
            blackOutOtherScreens: false,
            fullscreenControlBar: 0,     // 0=Auto-hide 3s, 1=Auto-hide 5s, 2=Always
            timeOSDPosition: 0,          // 0=Top-left, 1=Top-center, 2=Top-right, 3=Hidden
            filterSharpen: false,
            filterSharpenSigma: 0.5,
            filterGrain: false,
            filterGrainVariance: 1.0,
            filterPosterize: false,
            filterInvert: false,
            filterMirror: false,
            preventSleepWhilePlaying: true,
            allowScreenSaverForAudio: true,
            mediaKeyEnabled: true,
            escapeKeyBehavior: 0,        // 0=Exit Fullscreen, 1=Close Panel, 2=Stop Playback
            singleClickAction: 0,        // 0=Play/Pause, 1=Nothing
            doubleClickAction: 0,        // 0=Toggle Fullscreen, 1=Nothing
            middleClickAction: 0,        // 0=Mute/Unmute, 1=Play/Pause, 2=Nothing
            rightClickAction: 0,         // 0=Context Menu, 1=Nothing
            scrollWheelAction: 0,        // 0=Volume, 1=Seek, 2=Nothing
            scrollWheelSensitivity: 5.0,
            pinchGestureAction: 0,       // 0=Zoom Video, 1=Resize Window, 2=Nothing
            castDefaultBehavior: 0,      // 0=Ask every time, 1=Auto-connect
            autoDisconnectOnClose: true,
            resumeLocalOnDisconnect: true,
            airplayButtonVisibility: 0,  // 0=Always, 1=When available, 2=Never
            chromecastQuality: 1,        // 0=Low, 1=Medium, 2=High
            dlnaQuality: 1,              // 0=Low, 1=Medium, 2=High
            convertHardwareEncoding: true,
            // KeyBindingManager.loadBindings handles a nil/missing value by
            // falling back to the "default" preset, but registering an
            // explicit empty Data here keeps the audit clean (every declared
            // key has a registered default).
            customShortcuts: Data(),
        ])
    }
}
