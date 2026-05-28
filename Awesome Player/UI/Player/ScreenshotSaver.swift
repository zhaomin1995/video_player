/// Snapshots the currently-playing frame to disk.
///
/// Branches on whether AVPlayer or libvlc is driving playback because the
/// two engines have totally different snapshot APIs:
///   - AVPlayer: AVAssetImageGenerator with zero tolerance — gives us a
///     frame-accurate still in the user's chosen format (PNG/JPEG/TIFF).
///   - libvlc: takeSnapshot writes a PNG directly. We don't get format
///     choice; libvlc's snapshot module is PNG-only at runtime.
///
/// Save location and image format both read from the same UserDefaults keys
/// the Video preferences pane writes, so a change in preferences is picked
/// up on the next screenshot.
import Cocoa
import AVFoundation

enum ScreenshotSaver {
    enum Result {
        case saved(directoryName: String)
        case failed
        case noVideo
    }

    static func save(playerEngine: AVPlayerEngine?,
                     vlcEngine: VLCPlayerEngine?,
                     completion: @escaping (Result) -> Void) {
        if playerEngine == nil, let vlc = vlcEngine {
            let dir = savePathURL()
            let filename = "Awesome Player \(timestamp()).png"
            let path = dir.appendingPathComponent(filename).path
            let ok = vlc.takeSnapshot(path: path)
            DispatchQueue.main.async {
                completion(ok ? .saved(directoryName: savePathName()) : .failed)
            }
            return
        }
        guard let player = playerEngine?.player, let item = player.currentItem else {
            DispatchQueue.main.async { completion(.noVideo) }
            return
        }
        let time = player.currentTime()
        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        DispatchQueue.global(qos: .userInitiated).async {
            var actualTime = CMTime.zero
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: &actualTime) else {
                DispatchQueue.main.async { completion(.failed) }
                return
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            let (fileType, ext) = imageFormat()
            guard let data = rep.representation(using: fileType, properties: [:]) else {
                DispatchQueue.main.async { completion(.failed) }
                return
            }
            let dir = savePathURL()
            let filename = "Awesome Player \(timestamp()).\(ext)"
            do {
                try data.write(to: dir.appendingPathComponent(filename))
                DispatchQueue.main.async { completion(.saved(directoryName: savePathName())) }
            } catch {
                // Was a silent try? — sandbox can deny writes to e.g. Pictures
                // if the user revoked permission. Surface to OSD so the user
                // can change the save path in Preferences.
                wlog(.player, "Screenshot write failed: \(error)")
                DispatchQueue.main.async { completion(.failed) }
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }

    private static func savePathURL() -> URL {
        let idx = UserDefaults.standard.integer(forKey: Defaults.screenshotSavePath)
        let fm = FileManager.default
        switch idx {
        case 1: return fm.urls(for: .picturesDirectory, in: .userDomainMask).first!
        case 2: return fm.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        default: return fm.urls(for: .desktopDirectory, in: .userDomainMask).first!
        }
    }

    private static func savePathName() -> String {
        let idx = UserDefaults.standard.integer(forKey: Defaults.screenshotSavePath)
        switch idx {
        case 1: return "Pictures"
        case 2: return "Downloads"
        default: return "Desktop"
        }
    }

    private static func imageFormat() -> (NSBitmapImageRep.FileType, String) {
        let idx = UserDefaults.standard.integer(forKey: Defaults.screenshotFormat)
        switch idx {
        case 1: return (.jpeg, "jpg")
        case 2: return (.tiff, "tiff")
        default: return (.png, "png")
        }
    }
}
