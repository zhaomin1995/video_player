/// Wraps AVPlayer with KVO-based status tracking and periodic time observation.
/// Uses modern `NSKeyValueObservation` (block-based KVO) to avoid the fragile
/// selector-based `observeValue(forKeyPath:)` pattern. Duration is loaded
/// asynchronously via `AVAsset.load(_:)` because synchronous access blocks
/// the main thread for network/large assets.
import AVFoundation
import Cocoa

protocol AVPlayerEngineDelegate: AnyObject {
    func playerEngineTimeDidChange(current: Double, duration: Double)
    func playerEngineDidFinishPlaying()
    func playerEngineDidUpdateStatus(isPlaying: Bool)
    func playerEngineExternalPlaybackChanged(isActive: Bool)
}

class AVPlayerEngine: NSObject {
    weak var delegate: AVPlayerEngineDelegate?

    private(set) var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    // Block-based KVO observations — automatically invalidated when set to nil
    private var rateObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var externalPlaybackObservation: NSKeyValueObservation?

    var isPlaying: Bool {
        player?.rate != 0
    }

    /// Cache duration to avoid repeated CMTime conversions on every time tick
    private var cachedDuration: Double = 0

    var duration: Double {
        if cachedDuration > 0 { return cachedDuration }
        let d = playerItem?.duration.seconds ?? 0
        if d.isFinite && d > 0 { cachedDuration = d }
        return cachedDuration
    }

    var currentTime: Double {
        player?.currentTime().seconds ?? 0
    }

    var volume: Float {
        get { player?.volume ?? 1.0 }
        set { player?.volume = max(0, min(1, newValue)) }
    }

    var isMuted: Bool {
        get { player?.isMuted ?? false }
        set { player?.isMuted = newValue }
    }

    private var desiredRate: Float = 1.0

    var rate: Float {
        get { desiredRate }
        set {
            desiredRate = newValue
            if isPlaying {
                player?.rate = newValue
            }
        }
    }

    /// Kept for API compatibility — no longer used since seek tolerance is now
    /// chosen per-call (keyframe for interactive seeks, precise for jumps).
    var useKeyframeSeeking = false

    var videoSize: NSSize? {
        guard let track = playerItem?.asset.tracks(withMediaType: .video).first else { return nil }
        // Apply preferredTransform to handle rotated videos (e.g. portrait iPhone footage)
        let size = track.naturalSize.applying(track.preferredTransform)
        return NSSize(width: abs(size.width), height: abs(size.height))
    }

    /// Set false for Dolby Vision files where we don't want AVKit's AirPlay
    /// path engaging (Samsung AirPlay 2 receivers won't decode P5 over AVKit;
    /// we route DV via libvlc renderer instead). Must be set before open().
    var allowsExternalPlayback: Bool = true

    func open(url: URL) {
        stop()
        cachedDuration = 0

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        playerItem = item

        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.allowsExternalPlayback = allowsExternalPlayback
        avPlayer.volume = 1.0
        avPlayer.isMuted = false
        // Default `true` makes AVPlayer pause briefly after seeks to refill its
        // stall-protection buffer before showing the next frame. For local file
        // playback that buffer protection is wasted work and adds 100-300ms of
        // perceived seek lag on every interaction. VLC/Movist don't have an
        // equivalent layer, which is why their seeks feel snappier than ours
        // even though the underlying VideoToolbox decoder is identical.
        avPlayer.automaticallyWaitsToMinimizeStalling = false
        // Small forward buffer (5s) so a far-jump seek discards minimal data
        // and the refill at the new position is quick. Default is "system
        // decides" which can be 30-60s on macOS for HD content — that's a lot
        // of decode pipeline to tear down and rebuild on every random seek.
        item.preferredForwardBufferDuration = 5
        player = avPlayer

        dlog(.avplayer, "Created player for: \(url.lastPathComponent), volume=\(avPlayer.volume), muted=\(avPlayer.isMuted)")

        setupTimeObserver()
        setupNotifications()
        observeStatus()
        observeItemStatus()
        observeExternalPlayback()

        // Load duration asynchronously — AVAsset.duration blocks until the
        // asset header is fully parsed, which is slow for large/network files.
        Task {
            if let dur = try? await asset.load(.duration) {
                let secs = dur.seconds
                if secs.isFinite && secs > 0 {
                    await MainActor.run {
                        self.cachedDuration = secs
                        self.delegate?.playerEngineTimeDidChange(current: 0, duration: secs)
                    }
                }
            }
        }
    }

    func play() {
        player?.rate = desiredRate
        dlog(.avplayer, "play() called, rate=\(player?.rate ?? 0), volume=\(player?.volume ?? 0), status=\(playerItem?.status.rawValue ?? -1)")
        delegate?.playerEngineDidUpdateStatus(isPlaying: true)
    }

    func pause() {
        player?.pause()
        delegate?.playerEngineDidUpdateStatus(isPlaying: false)
    }

    /// Tears down everything — must nil out KVO observations before releasing
    /// the player, otherwise observers fire on a deallocated object.
    func stop() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        rateObservation = nil
        itemStatusObservation = nil
        externalPlaybackObservation = nil
        player?.pause()
        player = nil
        playerItem = nil
        NotificationCenter.default.removeObserver(self)
    }

    /// Interactive arrow-key skip — keyframe seek for instant response.
    func seek(by seconds: Double) {
        guard let player = player else { return }
        let current = player.currentTime()
        let target = CMTimeAdd(current, CMTimeMakeWithSeconds(seconds, preferredTimescale: 600))
        fastSeek(to: target, precise: false)
    }

    /// Progress-bar scrub — keyframe seek so the slider doesn't lag behind
    /// the click while AVPlayer decodes forward from the keyframe to an
    /// exact-frame target. Worst case the playhead lands 1–2s off the
    /// click position (one GOP); precise tolerance for 4K HEVC costs
    /// 100–500ms per seek which is much worse perceptually.
    func seekToFraction(_ fraction: Double) {
        guard let item = playerItem else { return }
        let dur = item.duration.seconds
        guard dur.isFinite, dur > 0 else { return }
        let target = CMTimeMakeWithSeconds(dur * fraction, preferredTimescale: 600)
        fastSeek(to: target, precise: false)
    }

    /// Programmatic jump to an exact timestamp (chapter nav, jump-to-time,
    /// resume from saved position). Uses precise tolerance because the
    /// caller picked the timestamp deliberately.
    func seekTo(time: Double) {
        let target = CMTimeMakeWithSeconds(time, preferredTimescale: 600)
        fastSeek(to: target, precise: true)
    }

    /// Fires the seek immediately and returns. We don't wait for completion
    /// or coalesce — AVPlayer already cancels any in-flight seek when a new
    /// `seek(to:)` arrives, so the most recent target always wins. The old
    /// "wait for completion, then dequeue pending" pattern actually doubled
    /// perceived seek latency on drags because mouseUp's seek wouldn't start
    /// until mouseDown's seek finished its visual settle (~100-300ms).
    /// `cancelPendingSeeks` explicitly aborts any in-flight handler so we
    /// don't accumulate stale completions.
    private func fastSeek(to target: CMTime, precise: Bool) {
        guard let player = player else { return }
        playerItem?.cancelPendingSeeks()
        let tolerance: CMTime = precise
            ? CMTimeMakeWithSeconds(0.1, preferredTimescale: 600)
            : .positiveInfinity
        player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    // MARK: - Track Switching

    struct TrackInfo {
        let index: Int
        let name: String
        let languageCode: String?
    }

    func getAudioTracks() -> [TrackInfo] {
        guard let item = playerItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return [] }
        return group.options.enumerated().map { (i, option) in
            let name = option.displayName
            let lang = option.extendedLanguageTag
            return TrackInfo(index: i, name: name, languageCode: lang)
        }
    }

    func getSubtitleTracks() -> [TrackInfo] {
        guard let item = playerItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return [] }
        return group.options.enumerated().map { (i, option) in
            let name = option.displayName
            let lang = option.extendedLanguageTag
            return TrackInfo(index: i, name: name, languageCode: lang)
        }
    }

    func selectAudioTrack(at index: Int) {
        guard let item = playerItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              index < group.options.count else { return }
        item.select(group.options[index], in: group)
    }

    func selectSubtitleTrack(at index: Int) {
        guard let item = playerItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        if index < 0 {
            item.select(nil, in: group)
        } else if index < group.options.count {
            item.select(group.options[index], in: group)
        }
    }

    func stepFrame(forward: Bool) {
        guard let item = playerItem else { return }
        if isPlaying { pause() }
        item.step(byCount: forward ? 1 : -1)
    }

    private func setupTimeObserver() {
        let interval = CMTimeMakeWithSeconds(0.25, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let current = time.seconds
            let dur = self.duration
            if current.isFinite && dur.isFinite {
                self.delegate?.playerEngineTimeDidChange(current: current, duration: dur)
            }
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
    }

    /// Track rate changes to detect play/pause initiated externally (e.g. AirPlay remote)
    private func observeStatus() {
        rateObservation = player?.observe(\.rate, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.delegate?.playerEngineDidUpdateStatus(isPlaying: player.rate != 0)
            }
        }
    }

    /// Observe .readyToPlay to grab the final duration — the async Task in open()
    /// may resolve first for local files, but this handles cases where it doesn't
    /// (e.g. the asset load was cancelled or the item resolves from a different source).
    private func observeItemStatus() {
        itemStatusObservation = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            dlog(.avplayer, "Item status changed: \(item.status.rawValue) error: \(item.error?.localizedDescription ?? "none")")
            guard let self = self, item.status == .readyToPlay else { return }
            let dur = item.duration.seconds
            if dur.isFinite && dur > 0 {
                DispatchQueue.main.async {
                    self.cachedDuration = dur
                    self.delegate?.playerEngineTimeDidChange(current: self.currentTime, duration: dur)
                }
            }
        }
    }

    /// Detect when AirPlay video streaming activates/deactivates so the UI
    /// can show feedback and the local player layer can go blank gracefully.
    private func observeExternalPlayback() {
        externalPlaybackObservation = player?.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                let active = player.isExternalPlaybackActive
                dlog(.avplayer, "External playback: \(active)")
                self?.delegate?.playerEngineExternalPlaybackChanged(isActive: active)
            }
        }
    }

    @objc private func playerDidFinish(_ notification: Notification) {
        delegate?.playerEngineDidFinishPlaying()
    }

    deinit {
        stop()
    }
}
