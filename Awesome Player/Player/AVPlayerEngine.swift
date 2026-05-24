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
    private var statusObservation: NSKeyValueObservation?
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

    var rate: Float {
        get { player?.rate ?? 1.0 }
        set {
            if isPlaying {
                player?.rate = newValue
            }
        }
    }

    var useKeyframeSeeking = false

    private var seekTolerance: CMTime {
        useKeyframeSeeking ? .positiveInfinity : .zero
    }

    var videoSize: NSSize? {
        guard let track = playerItem?.asset.tracks(withMediaType: .video).first else { return nil }
        // Apply preferredTransform to handle rotated videos (e.g. portrait iPhone footage)
        let size = track.naturalSize.applying(track.preferredTransform)
        return NSSize(width: abs(size.width), height: abs(size.height))
    }

    func open(url: URL) {
        stop()

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        playerItem = item

        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.allowsExternalPlayback = true
        avPlayer.volume = 1.0
        avPlayer.isMuted = false
        player = avPlayer

        print("[AVPlayerEngine] Created player for: \(url.lastPathComponent), volume=\(avPlayer.volume), muted=\(avPlayer.isMuted)")

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
        player?.play()
        print("[AVPlayerEngine] play() called, rate=\(player?.rate ?? 0), volume=\(player?.volume ?? 0), status=\(playerItem?.status.rawValue ?? -1)")
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
        statusObservation = nil
        rateObservation = nil
        itemStatusObservation = nil
        externalPlaybackObservation = nil
        player?.pause()
        player = nil
        playerItem = nil
        NotificationCenter.default.removeObserver(self)
    }

    func seek(by seconds: Double) {
        guard let player = player else { return }
        let current = player.currentTime()
        let target = CMTimeAdd(current, CMTimeMakeWithSeconds(seconds, preferredTimescale: 600))
        player.seek(to: target, toleranceBefore: seekTolerance, toleranceAfter: seekTolerance)
    }

    func seekToFraction(_ fraction: Double) {
        guard let item = playerItem else { return }
        let dur = item.duration.seconds
        guard dur.isFinite, dur > 0 else { return }
        let target = CMTimeMakeWithSeconds(dur * fraction, preferredTimescale: 600)
        player?.seek(to: target, toleranceBefore: seekTolerance, toleranceAfter: seekTolerance)
    }

    func seekTo(time: Double) {
        let target = CMTimeMakeWithSeconds(time, preferredTimescale: 600)
        player?.seek(to: target, toleranceBefore: seekTolerance, toleranceAfter: seekTolerance)
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
            print("[AVPlayerEngine] Item status changed: \(item.status.rawValue) error: \(item.error?.localizedDescription ?? "none")")
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
                print("[AVPlayerEngine] External playback: \(active)")
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
