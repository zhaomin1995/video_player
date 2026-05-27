/// VLC-based playback engine using libvlc from VLC.app.
/// Handles any container/codec VLC supports — instant playback, no remuxing.
/// Uses libvlc event manager for time/position updates instead of polling.
import Cocoa

/// 10-band custom EQ preset. Bands target the standard ISO frequencies
/// libvlc uses (60, 170, 310, 600, 1k, 3k, 6k, 12k, 14k, 16k Hz). Values
/// are in dB, range typically [-20, +20]. Preset values mirror the macOS
/// Music app / Movist Pro defaults so users see familiar behavior.
struct AudioEqualizerPreset {
    let name: String
    let preamp: Float
    let bands: [Float]   // 10 values, one per ISO band

    static let all: [AudioEqualizerPreset] = [
        AudioEqualizerPreset(name: "Flat",            preamp: 0,   bands: [ 0,    0,    0,    0,    0,    0,    0,    0,    0,    0  ]),
        AudioEqualizerPreset(name: "Acoustic",        preamp: 6,   bands: [ 5,    4.5,  3.5,  1,    1.5,  1.5,  3.5,  3.5,  3.5,  2.5]),
        AudioEqualizerPreset(name: "Bass Booster",    preamp: 6,   bands: [ 5.5,  4.5,  3.5,  2.5,  1,    0,    0,    0,    0,    0  ]),
        AudioEqualizerPreset(name: "Bass Reducer",    preamp: 0,   bands: [-5.5, -4.5, -3.5, -2.5, -1,    0,    0,    0,    0,    0  ]),
        AudioEqualizerPreset(name: "Classical",       preamp: 0,   bands: [ 0,    0,    0,    0,    0,    0,   -4,   -4,   -4,   -5.5]),
        AudioEqualizerPreset(name: "Dance",           preamp: 6,   bands: [ 4.5,  6.5,  5,    0,    1.5,  3,    4,    4,    4,    0  ]),
        AudioEqualizerPreset(name: "Deep",            preamp: 6,   bands: [ 5,    3,    1.5,  1,    3,    1.5, -2,   -3.5, -4,   -4.5]),
        AudioEqualizerPreset(name: "Electronic",      preamp: 6,   bands: [ 4.5,  3.5,  1,    0,   -2,    2,    1,    1,    4,    4.5]),
        AudioEqualizerPreset(name: "Hip-Hop",         preamp: 6,   bands: [ 5,    4,    1.5,  3,   -1,   -1,    1.5, -0.5,  1.5,  3  ]),
        AudioEqualizerPreset(name: "Jazz",            preamp: 6,   bands: [ 4,    3,    1.5,  2,   -2,   -2,    0,    1.5,  3,    4  ]),
        AudioEqualizerPreset(name: "Latin",           preamp: 6,   bands: [ 4.5,  3,    0,    0,   -2,   -2,   -2,    0,    3,    4.5]),
        AudioEqualizerPreset(name: "Loudness",        preamp: 6,   bands: [ 5.5,  4,    0,    0,   -2,    0,   -1,   -5,    5,    1  ]),
        AudioEqualizerPreset(name: "Lounge",          preamp: 3,   bands: [-3,   -2,   -1,    1,    4,    2.5,  0,   -2,    2,    1  ]),
        AudioEqualizerPreset(name: "Perfect :)",      preamp: 4,   bands: [ 3,    2,    1.5,  1,    1,    1,    2,    2,    2.5,  3  ]),
        AudioEqualizerPreset(name: "Piano",           preamp: 4,   bands: [ 3,    2,    0,    2.5,  3,    1,    3,    4.5,  3,    3.5]),
        AudioEqualizerPreset(name: "Pop",             preamp: 4,   bands: [-1.5, -1,    0,    2,    4.5,  4.5,  2,   -1,   -1.5, -1.5]),
        AudioEqualizerPreset(name: "R&B",             preamp: 6,   bands: [ 3,    7,    6,    1,   -2,   -1.5,  2,    2.5,  3,    4  ]),
        AudioEqualizerPreset(name: "Rock",            preamp: 6,   bands: [ 5,    4,    3,    1.5, -0.5, -1,    0.5,  3,    4,    4.5]),
        AudioEqualizerPreset(name: "Small Speakers",  preamp: 6,   bands: [ 5,    4,    3,    2,    1,    0,   -2,   -3,   -4,   -5  ]),
        AudioEqualizerPreset(name: "Spoken Word",     preamp: 3,   bands: [-3,   -0.5,  0,    0.5,  3,    3.5,  4,    3.5,  3,    0  ]),
        AudioEqualizerPreset(name: "Treble Booster",  preamp: 6,   bands: [ 0,    0,    0,    0,    0,    1,    3,    4.5,  5,    5.5]),
        AudioEqualizerPreset(name: "Treble Reducer",  preamp: 0,   bands: [ 0,    0,    0,    0,    0,   -1,   -3,   -4.5, -5,   -5.5]),
        AudioEqualizerPreset(name: "Vocal Booster",   preamp: 4,   bands: [-1.5, -3,   -3,    1.5,  3.5,  3.5,  2.5,  1.5,  0,   -1.5]),
    ]
}

protocol VLCPlayerEngineDelegate: AnyObject {
    func vlcEngineTimeDidChange(current: Double, duration: Double)
    func vlcEngineDidFinishPlaying()
    func vlcEngineDidUpdateStatus(isPlaying: Bool)
}

class VLCPlayerEngine {
    weak var delegate: VLCPlayerEngineDelegate?

    private static var sharedVLCInstance: OpaquePointer? = {
        // Use VLC.app's plugin directory if available (pre-built cache, faster startup)
        let vlcAppPlugins = "/Applications/VLC.app/Contents/MacOS/plugins"
        let bundledPlugins = Bundle.main.bundlePath + "/Contents/plugins"
        let pluginPath = FileManager.default.fileExists(atPath: vlcAppPlugins) ? vlcAppPlugins : bundledPlugins
        let args: [String] = [
            "--no-video-title-show", "--no-stats", "--no-snapshot-preview",
            "--vout=caopengllayer",
        ]
        setenv("VLC_PLUGIN_PATH", pluginPath, 1)
        if FileManager.default.fileExists(atPath: "/Applications/VLC.app/Contents/MacOS/lib") {
            setenv("DYLD_LIBRARY_PATH", "/Applications/VLC.app/Contents/MacOS/lib", 1)
        }
        var cStrings = args.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        var ptrs = cStrings.map { UnsafePointer<CChar>($0) as UnsafePointer<CChar>? }
        let inst = ptrs.withUnsafeMutableBufferPointer { buf in
            libvlc_new(Int32(args.count), buf.baseAddress!)
        }
        if inst != nil { print("[VLCEngine] Shared libvlc instance created") }
        return inst
    }()

    /// Force VLC plugin loading now so file opens are instant.
    static func preload() {
        _ = sharedVLCInstance
    }

    /// Exposed for headless users of libvlc (e.g. the Convert/Stream window
    /// which uses a separate media player for transcode pipelines).
    static var sharedInstance: OpaquePointer? { sharedVLCInstance }

    private var instance: OpaquePointer?
    private(set) var player: OpaquePointer?
    private var media: OpaquePointer?
    private var eventManager: OpaquePointer?

    private(set) var isPlaying = false
    private(set) var duration: Double = 0

    /// The NSView that libvlc renders into
    let renderView = NSView()

    var currentTime: Double {
        guard let p = player else { return 0 }
        return Double(libvlc_media_player_get_time(p)) / 1000.0
    }

    var volume: Float {
        get {
            guard let p = player else { return 1.0 }
            return Float(libvlc_audio_get_volume(p)) / 100.0
        }
        set {
            guard let p = player else { return }
            libvlc_audio_set_volume(p, Int32(newValue * 100))
        }
    }

    var isMuted: Bool {
        get {
            guard let p = player else { return false }
            return libvlc_audio_get_mute(p) != 0
        }
        set {
            guard let p = player else { return }
            libvlc_audio_set_mute(p, newValue ? 1 : 0)
        }
    }

    var rate: Float {
        get {
            guard let p = player else { return 1.0 }
            return libvlc_media_player_get_rate(p)
        }
        set {
            guard let p = player else { return }
            libvlc_media_player_set_rate(p, newValue)
        }
    }

    private var equalizer: OpaquePointer?

    var videoSize: NSSize? {
        guard let p = player else { return nil }
        var w: UInt32 = 0, h: UInt32 = 0
        if libvlc_video_get_size(p, 0, &w, &h) == 0, w > 0, h > 0 {
            return NSSize(width: CGFloat(w), height: CGFloat(h))
        }
        return nil
    }

    init() {
        instance = Self.sharedVLCInstance
        if instance == nil {
            print("[VLCEngine] Failed to get libvlc instance")
        }
    }

    deinit {
        stop()
    }

    func open(url: URL, audioURL: URL? = nil) -> Bool {
        guard let inst = instance else { return false }

        if url.isFileURL {
            media = libvlc_media_new_path(inst, url.path)
        } else {
            media = libvlc_media_new_location(inst, url.absoluteString)
        }
        guard media != nil else {
            print("[VLCEngine] Failed to create media for: \(url.absoluteString)")
            return false
        }

        if let audioURL = audioURL {
            let slave = ":input-slave=\(audioURL.absoluteString)"
            libvlc_media_add_option(media, slave)
        }

        // Apply audio normalization if enabled
        if let m = media {
            if UserDefaults.standard.bool(forKey: Defaults.normalizationEnabled) {
                libvlc_media_add_option(m, "--audio-filter=normvol")
            }
            if UserDefaults.standard.bool(forKey: Defaults.compressorEnabled) {
                libvlc_media_add_option(m, "--audio-filter=compressor")
            }
            // Snap seeks to the nearest keyframe instead of decoding forward
            // to an exact frame. Trades up to ~1s of seek-position accuracy
            // for sub-100ms response. Matches what the AVPlayer path now does
            // (positive-infinity tolerance) so both engines feel equally snappy.
            libvlc_media_add_option(m, ":input-fast-seek")
            // libvlc defaults file-caching to 1000ms — after every seek it
            // buffers a full second of demuxed media before resuming playback.
            // That is literally the "1s seek lag" we see with the libvlc path
            // (and the same lag VLC.app has). Movist Pro avoids it because it
            // uses FFmpeg directly without libvlc's input-buffer layer. 100ms
            // is enough to absorb any disk-read jitter on local files.
            libvlc_media_add_option(m, ":file-caching=100")
            libvlc_media_add_option(m, ":network-caching=300")
        }

        player = libvlc_media_player_new_from_media(media)
        guard let p = player else { return false }

        renderView.wantsLayer = true
        libvlc_media_player_set_nsobject(p, Unmanaged.passUnretained(renderView).toOpaque())

        duration = 0
        attachEvents()

        print("[VLCEngine] Opened: \(url.lastPathComponent)")
        return true
    }

    func play() {
        guard let p = player else { return }
        libvlc_media_player_play(p)
        isPlaying = true
        delegate?.vlcEngineDidUpdateStatus(isPlaying: true)
    }

    func pause() {
        guard let p = player else { return }
        libvlc_media_player_pause(p)
        isPlaying = false
        delegate?.vlcEngineDidUpdateStatus(isPlaying: false)
    }

    func seek(by seconds: Double) {
        let target = currentTime + seconds
        if duration > 0 {
            seekTo(time: max(0, min(duration, target)))
        } else {
            seekTo(time: max(0, target))
        }
    }

    func seekTo(time: Double) {
        guard let p = player else { return }
        restartIfEnded()
        libvlc_media_player_set_time(p, Int64(time * 1000))
    }

    func seekToFraction(_ fraction: Double) {
        guard let p = player else { return }
        restartIfEnded()
        libvlc_media_player_set_position(p, Float(fraction))
    }

    private func restartIfEnded() {
        guard let p = player else { return }
        let state = libvlc_media_player_get_state(p)
        if state == libvlc_Ended || state == libvlc_Stopped {
            libvlc_media_player_stop(p)
            libvlc_media_player_play(p)
            isPlaying = true
            delegate?.vlcEngineDidUpdateStatus(isPlaying: true)
        }
    }

    func stop() {
        detachEvents()
        if let eq = equalizer {
            libvlc_audio_equalizer_release(eq)
            equalizer = nil
        }
        if let p = player {
            libvlc_media_player_stop(p)
            libvlc_media_player_release(p)
        }
        if let m = media { libvlc_media_release(m) }
        player = nil
        media = nil
        eventManager = nil
        isPlaying = false
    }

    // MARK: - Frame Stepping

    func stepFrame() {
        guard let p = player else { return }
        if isPlaying { pause() }
        libvlc_media_player_next_frame(p)
    }

    // MARK: - Event-Driven Updates

    private var eventContext: Unmanaged<VLCPlayerEngine>?

    private func attachEvents() {
        guard let p = player else { return }
        eventManager = libvlc_media_player_event_manager(p)
        guard let em = eventManager else { return }

        eventContext = Unmanaged.passRetained(self)
        let ctx = eventContext!.toOpaque()

        libvlc_event_attach(em, Int32(libvlc_MediaPlayerTimeChanged), vlcTimeChanged, ctx)
        libvlc_event_attach(em, Int32(libvlc_MediaPlayerLengthChanged), vlcLengthChanged, ctx)
        libvlc_event_attach(em, Int32(libvlc_MediaPlayerEndReached), vlcEndReached, ctx)
        libvlc_event_attach(em, Int32(libvlc_MediaPlayerPlaying), vlcPlaying, ctx)
        libvlc_event_attach(em, Int32(libvlc_MediaPlayerPaused), vlcPaused, ctx)
        libvlc_event_attach(em, Int32(libvlc_MediaPlayerStopped), vlcStopped, ctx)
    }

    private func detachEvents() {
        guard let em = eventManager, let ctx = eventContext else { return }
        let ptr = ctx.toOpaque()

        libvlc_event_detach(em, Int32(libvlc_MediaPlayerTimeChanged), vlcTimeChanged, ptr)
        libvlc_event_detach(em, Int32(libvlc_MediaPlayerLengthChanged), vlcLengthChanged, ptr)
        libvlc_event_detach(em, Int32(libvlc_MediaPlayerEndReached), vlcEndReached, ptr)
        libvlc_event_detach(em, Int32(libvlc_MediaPlayerPlaying), vlcPlaying, ptr)
        libvlc_event_detach(em, Int32(libvlc_MediaPlayerPaused), vlcPaused, ptr)
        libvlc_event_detach(em, Int32(libvlc_MediaPlayerStopped), vlcStopped, ptr)

        ctx.release()
        eventContext = nil
    }

    fileprivate func handleTimeChanged(_ timeMs: Int64) {
        let time = Double(timeMs) / 1000.0
        delegate?.vlcEngineTimeDidChange(current: time, duration: duration)
    }

    fileprivate func handleLengthChanged(_ lengthMs: Int64) {
        let len = Double(lengthMs) / 1000.0
        if len > 0 { duration = len }
    }

    fileprivate func handleEndReached() {
        isPlaying = false
        delegate?.vlcEngineDidFinishPlaying()
        delegate?.vlcEngineDidUpdateStatus(isPlaying: false)
    }

    fileprivate func handlePlaying() {
        isPlaying = true
        delegate?.vlcEngineDidUpdateStatus(isPlaying: true)
    }

    fileprivate func handlePaused() {
        isPlaying = false
        delegate?.vlcEngineDidUpdateStatus(isPlaying: false)
    }

    fileprivate func handleStopped() {
        isPlaying = false
        delegate?.vlcEngineDidUpdateStatus(isPlaying: false)
    }

    // MARK: - Track Switching

    struct TrackInfo {
        let id: Int
        let name: String
    }

    func getAudioTracks() -> [TrackInfo] {
        guard let p = player else { return [] }
        return parseTrackDescriptions(libvlc_audio_get_track_description(p))
    }

    func getSubtitleTracks() -> [TrackInfo] {
        guard let p = player else { return [] }
        return parseTrackDescriptions(libvlc_video_get_spu_description(p))
    }

    func getVideoTracks() -> [TrackInfo] {
        guard let p = player else { return [] }
        return parseTrackDescriptions(libvlc_video_get_track_description(p))
    }

    func getCurrentAudioTrack() -> Int {
        guard let p = player else { return -1 }
        return Int(libvlc_audio_get_track(p))
    }

    func getCurrentSubtitleTrack() -> Int {
        guard let p = player else { return -1 }
        return Int(libvlc_video_get_spu(p))
    }

    func setAudioTrack(_ trackId: Int) {
        guard let p = player else { return }
        libvlc_audio_set_track(p, Int32(trackId))
    }

    func setSubtitleTrack(_ trackId: Int) {
        guard let p = player else { return }
        libvlc_video_set_spu(p, Int32(trackId))
    }

    func setVideoTrack(_ trackId: Int) {
        guard let p = player else { return }
        libvlc_video_set_track(p, Int32(trackId))
    }

    func addSubtitleFile(_ path: String) {
        guard let p = player else { return }
        let uri = URL(fileURLWithPath: path).absoluteString
        libvlc_media_player_add_slave(p, libvlc_media_slave_type_subtitle, uri, 1)
    }

    private func parseTrackDescriptions(_ head: UnsafeMutablePointer<libvlc_track_description_t>?) -> [TrackInfo] {
        var tracks: [TrackInfo] = []
        var current = head
        while let desc = current {
            let name: String
            if let psz = desc.pointee.psz_name {
                name = String(cString: psz)
            } else {
                name = "Track \(desc.pointee.i_id)"
            }
            tracks.append(TrackInfo(id: Int(desc.pointee.i_id), name: name))
            current = desc.pointee.p_next
        }
        if let head = head {
            libvlc_track_description_list_release(head)
        }
        return tracks
    }

    // MARK: - Equalizer

    /// Applies a 10-band custom EQ preset by name. The preset's preamp +
    /// per-band amplification values come from `AudioEqualizerPreset.all`.
    /// `index == 0` means "Off" — disables EQ entirely.
    func setEqualizer(presetIndex: Int) {
        guard let p = player else { return }
        if let eq = equalizer { libvlc_audio_equalizer_release(eq); equalizer = nil }

        if presetIndex <= 0 {
            libvlc_media_player_set_equalizer(p, nil)
            return
        }

        let presets = AudioEqualizerPreset.all
        guard presetIndex - 1 < presets.count else { return }
        let preset = presets[presetIndex - 1]

        guard let eq = libvlc_audio_equalizer_new() else { return }
        libvlc_audio_equalizer_set_preamp(eq, preset.preamp)
        let bandCount = min(preset.bands.count, Int(libvlc_audio_equalizer_get_band_count()))
        for i in 0..<bandCount {
            libvlc_audio_equalizer_set_amp_at_index(eq, preset.bands[i], UInt32(i))
        }
        equalizer = eq
        libvlc_media_player_set_equalizer(p, eq)
    }

    func disableEqualizer() {
        guard let p = player else { return }
        libvlc_media_player_set_equalizer(p, nil)
        if let eq = equalizer {
            libvlc_audio_equalizer_release(eq)
            equalizer = nil
        }
    }

    // MARK: - Audio Delay

    func setAudioDelay(seconds: Double) {
        guard let p = player else { return }
        libvlc_audio_set_delay(p, Int64(seconds * 1_000_000))
    }


    // MARK: - Snapshot

    func takeSnapshot(path: String, width: UInt32 = 0, height: UInt32 = 0) -> Bool {
        guard let p = player else { return false }
        return libvlc_video_take_snapshot(p, 0, path, width, height) == 0
    }

    // MARK: - Video Adjustments

    func setVideoAdjust(enabled: Bool) {
        guard let p = player else { return }
        libvlc_video_set_adjust_int(p, UInt32(libvlc_adjust_Enable), enabled ? 1 : 0)
    }

    func setBrightness(_ value: Float) {
        guard let p = player else { return }
        libvlc_video_set_adjust_int(p, UInt32(libvlc_adjust_Enable), 1)
        libvlc_video_set_adjust_float(p, UInt32(libvlc_adjust_Brightness), value)
    }

    func setContrast(_ value: Float) {
        guard let p = player else { return }
        libvlc_video_set_adjust_int(p, UInt32(libvlc_adjust_Enable), 1)
        libvlc_video_set_adjust_float(p, UInt32(libvlc_adjust_Contrast), value)
    }

    func setSaturation(_ value: Float) {
        guard let p = player else { return }
        libvlc_video_set_adjust_int(p, UInt32(libvlc_adjust_Enable), 1)
        libvlc_video_set_adjust_float(p, UInt32(libvlc_adjust_Saturation), value)
    }

    func setHue(_ value: Float) {
        guard let p = player else { return }
        libvlc_video_set_adjust_int(p, UInt32(libvlc_adjust_Enable), 1)
        libvlc_video_set_adjust_float(p, UInt32(libvlc_adjust_Hue), value)
    }

    func setGamma(_ value: Float) {
        guard let p = player else { return }
        libvlc_video_set_adjust_int(p, UInt32(libvlc_adjust_Enable), 1)
        libvlc_video_set_adjust_float(p, UInt32(libvlc_adjust_Gamma), value)
    }

    // MARK: - Deinterlace

    func setDeinterlace(mode: String?) {
        guard let p = player else { return }
        if let mode = mode {
            libvlc_video_set_deinterlace(p, mode)
        } else {
            libvlc_video_set_deinterlace(p, nil)
        }
    }

    // MARK: - Crop

    func setCropGeometry(_ geometry: String?) {
        guard let p = player else { return }
        if let g = geometry {
            libvlc_video_set_crop_geometry(p, g)
        } else {
            libvlc_video_set_crop_geometry(p, nil)
        }
    }

    // MARK: - Renderer Discovery & Output

    struct RendererInfo {
        let name: String
        let type: String
        let item: OpaquePointer // libvlc_renderer_item_t*
    }

    private var rendererDiscoverers: [OpaquePointer] = []
    private var rendererEventContexts: [Unmanaged<VLCPlayerEngine>] = []
    private(set) var discoveredRenderers: [RendererInfo] = []
    var onRendererDiscovered: (() -> Void)?

    func startRendererDiscovery() {
        stopRendererDiscovery()
        guard let inst = instance else { return }

        var descs: UnsafeMutablePointer<UnsafeMutablePointer<libvlc_rd_description_t>?>?
        let count = libvlc_renderer_discoverer_list_get(inst, &descs)
        guard count > 0, let list = descs else { return }

        for i in 0..<count {
            guard let desc = list[i],
                  let cName = desc.pointee.psz_name else { continue }
            let name = String(cString: cName)
            guard let rd = libvlc_renderer_discoverer_new(inst, name) else { continue }

            let em = libvlc_renderer_discoverer_event_manager(rd)
            let ctx = Unmanaged.passRetained(self)
            rendererEventContexts.append(ctx)
            let ptr = ctx.toOpaque()

            libvlc_event_attach(em, Int32(libvlc_RendererDiscovererItemAdded), vlcRendererAdded, ptr)
            libvlc_event_attach(em, Int32(libvlc_RendererDiscovererItemDeleted), vlcRendererRemoved, ptr)

            if libvlc_renderer_discoverer_start(rd) == 0 {
                rendererDiscoverers.append(rd)
            } else {
                libvlc_renderer_discoverer_release(rd)
                ctx.release()
                rendererEventContexts.removeLast()
            }
        }
        libvlc_renderer_discoverer_list_release(descs, count)
    }

    func stopRendererDiscovery() {
        for rd in rendererDiscoverers {
            libvlc_renderer_discoverer_stop(rd)
            libvlc_renderer_discoverer_release(rd)
        }
        rendererDiscoverers.removeAll()
        for ctx in rendererEventContexts {
            ctx.release()
        }
        rendererEventContexts.removeAll()
        for r in discoveredRenderers {
            libvlc_renderer_item_release(r.item)
        }
        discoveredRenderers.removeAll()
    }

    /// Returns 0 on success, negative on failure. Negative usually means the
    /// renderer was set after play() — libvlc requires renderer attachment
    /// before media playback begins.
    @discardableResult
    func setRenderer(_ renderer: RendererInfo?) -> Int32 {
        guard let p = player else { return -1 }
        if let r = renderer {
            return libvlc_media_player_set_renderer(p, r.item)
        } else {
            return libvlc_media_player_set_renderer(p, nil)
        }
    }

    fileprivate func handleRendererAdded(_ item: OpaquePointer) {
        let held = libvlc_renderer_item_hold(item)!
        let name = String(cString: libvlc_renderer_item_name(held))
        let type = String(cString: libvlc_renderer_item_type(held))
        let info = RendererInfo(name: name, type: type, item: held)
        discoveredRenderers.append(info)
        print("[VLCEngine] Renderer discovered: \(name) (\(type))")
        onRendererDiscovered?()
    }

    fileprivate func handleRendererRemoved(_ item: OpaquePointer) {
        discoveredRenderers.removeAll { r in
            if r.item == item {
                libvlc_renderer_item_release(r.item)
                return true
            }
            return false
        }
        onRendererDiscovered?()
    }
}

private func vlcRendererAdded(_ event: UnsafePointer<libvlc_event_t>?, _ userData: UnsafeMutableRawPointer?) {
    guard let event = event, let userData = userData else { return }
    let item = event.pointee.u.renderer_discoverer_item_added.item!
    let engine = Unmanaged<VLCPlayerEngine>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { engine.handleRendererAdded(item) }
}

private func vlcRendererRemoved(_ event: UnsafePointer<libvlc_event_t>?, _ userData: UnsafeMutableRawPointer?) {
    guard let event = event, let userData = userData else { return }
    let item = event.pointee.u.renderer_discoverer_item_deleted.item!
    let engine = Unmanaged<VLCPlayerEngine>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { engine.handleRendererRemoved(item) }
}

// MARK: - C Callbacks (must be free functions, not closures)

private func vlcTimeChanged(_ event: UnsafePointer<libvlc_event_t>?, _ userData: UnsafeMutableRawPointer?) {
    guard let event = event, let userData = userData else { return }
    let timeMs = event.pointee.u.media_player_time_changed.new_time
    let engine = Unmanaged<VLCPlayerEngine>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { engine.handleTimeChanged(timeMs) }
}

private func vlcLengthChanged(_ event: UnsafePointer<libvlc_event_t>?, _ userData: UnsafeMutableRawPointer?) {
    guard let event = event, let userData = userData else { return }
    let lengthMs = event.pointee.u.media_player_length_changed.new_length
    let engine = Unmanaged<VLCPlayerEngine>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { engine.handleLengthChanged(lengthMs) }
}

private func vlcEndReached(_ event: UnsafePointer<libvlc_event_t>?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData = userData else { return }
    let engine = Unmanaged<VLCPlayerEngine>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { engine.handleEndReached() }
}

private func vlcPlaying(_ event: UnsafePointer<libvlc_event_t>?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData = userData else { return }
    let engine = Unmanaged<VLCPlayerEngine>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { engine.handlePlaying() }
}

private func vlcPaused(_ event: UnsafePointer<libvlc_event_t>?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData = userData else { return }
    let engine = Unmanaged<VLCPlayerEngine>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { engine.handlePaused() }
}

private func vlcStopped(_ event: UnsafePointer<libvlc_event_t>?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData = userData else { return }
    let engine = Unmanaged<VLCPlayerEngine>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { engine.handleStopped() }
}
