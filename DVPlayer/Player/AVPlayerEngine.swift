import AVFoundation
import Cocoa

protocol AVPlayerEngineDelegate: AnyObject {
    func playerEngineTimeDidChange(current: Double, duration: Double)
    func playerEngineDidFinishPlaying()
    func playerEngineDidUpdateStatus(isPlaying: Bool)
}

class AVPlayerEngine: NSObject {
    weak var delegate: AVPlayerEngineDelegate?

    private(set) var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?

    var isPlaying: Bool {
        player?.rate != 0
    }

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

    var videoSize: NSSize? {
        guard let track = playerItem?.asset.tracks(withMediaType: .video).first else { return nil }
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

    func stop() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObservation = nil
        rateObservation = nil
        itemStatusObservation = nil
        player?.pause()
        player = nil
        playerItem = nil
        NotificationCenter.default.removeObserver(self)
    }

    func seek(by seconds: Double) {
        guard let player = player else { return }
        let current = player.currentTime()
        let target = CMTimeAdd(current, CMTimeMakeWithSeconds(seconds, preferredTimescale: 600))
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seekToFraction(_ fraction: Double) {
        guard let item = playerItem else { return }
        let dur = item.duration.seconds
        guard dur.isFinite, dur > 0 else { return }
        let target = CMTimeMakeWithSeconds(dur * fraction, preferredTimescale: 600)
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seekTo(time: Double) {
        let target = CMTimeMakeWithSeconds(time, preferredTimescale: 600)
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
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

    private func observeStatus() {
        rateObservation = player?.observe(\.rate, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.delegate?.playerEngineDidUpdateStatus(isPlaying: player.rate != 0)
            }
        }
    }

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

    @objc private func playerDidFinish(_ notification: Notification) {
        delegate?.playerEngineDidFinishPlaying()
    }

    deinit {
        stop()
    }
}
