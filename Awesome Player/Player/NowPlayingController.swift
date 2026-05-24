import Cocoa
import MediaPlayer
import AVFoundation

class NowPlayingController {
    weak var playerViewController: PlayerViewController?

    func setup() {
        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.addTarget { [weak self] _ in
            self?.playerViewController?.togglePlayPause()
            return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            self?.playerViewController?.togglePlayPause()
            return .success
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.playerViewController?.togglePlayPause()
            return .success
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            self?.playerViewController?.playNextTrack()
            return .success
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            self?.playerViewController?.playPreviousTrack()
            return .success
        }
        cc.skipForwardCommand.preferredIntervals = [15]
        cc.skipForwardCommand.addTarget { [weak self] event in
            guard let e = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            self?.playerViewController?.seek(by: e.interval)
            return .success
        }
        cc.skipBackwardCommand.preferredIntervals = [15]
        cc.skipBackwardCommand.addTarget { [weak self] event in
            guard let e = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            self?.playerViewController?.seek(by: -e.interval)
            return .success
        }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.playerViewController?.seekToAbsoluteTime(e.positionTime)
            return .success
        }
    }

    func updateNowPlaying(title: String, duration: Double, artwork: NSImage? = nil) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        if let image = artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func updateTime(elapsed: Double, rate: Double) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func updatePlaybackState(isPlaying: Bool) {
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
