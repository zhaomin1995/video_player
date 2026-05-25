import AVFoundation
import CoreMedia

enum HDRType: String {
    case sdr = "SDR"
    case hdr10 = "HDR10"
    case hlg = "HLG"
    case dolbyVision = "Dolby Vision"
}

enum VideoCodec: String {
    case h264 = "H.264"
    case hevc = "HEVC"
    case av1 = "AV1"
    case vp9 = "VP9"
    case prores = "ProRes"
    case unknown = "Unknown"
}

struct MediaInfo {
    let url: URL
    let videoCodec: VideoCodec
    let audioCodecName: String?
    let hdrType: HDRType
    let isDolbyVision: Bool
    let isDolbyAtmos: Bool
    let videoSize: CGSize?
    let duration: Double
    let bitrate: Int?
    let isAVPlayerCompatible: Bool

    static func probe(url: URL) async -> MediaInfo {
        let asset = AVURLAsset(url: url)

        var videoCodec = VideoCodec.unknown
        var hdrType = HDRType.sdr
        var isDolbyVision = false
        var isDolbyAtmos = false
        var audioCodecName: String?
        var videoSize: CGSize?
        var isAVPlayerCompatible = url.isNativeAVPlayerFormat

        // Load tracks
        let videoTracks = try? await asset.loadTracks(withMediaType: .video)
        let audioTracks = try? await asset.loadTracks(withMediaType: .audio)

        // Analyze video tracks
        if let videoTrack = videoTracks?.first {
            let formatDescriptions = try? await videoTrack.load(.formatDescriptions)
            if let desc = formatDescriptions?.first {
                let codecType = CMFormatDescriptionGetMediaSubType(desc)
                videoCodec = mapCodecType(codecType)

                // Check HDR
                if let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] {
                    isDolbyVision = checkDolbyVision(extensions)
                    if isDolbyVision {
                        hdrType = .dolbyVision
                    } else {
                        hdrType = detectHDRType(extensions)
                    }
                }

                // AVPlayer compatibility
                isAVPlayerCompatible = isAVPlayerCompatible || isCodecAVPlayerCompatible(codecType)
            }

            let naturalSize = try? await videoTrack.load(.naturalSize)
            let transform = try? await videoTrack.load(.preferredTransform)
            if let size = naturalSize {
                if let t = transform {
                    let transformed = size.applying(t)
                    videoSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
                } else {
                    videoSize = size
                }
            }
        }

        // Analyze audio tracks
        if let audioTrack = audioTracks?.first {
            let formatDescriptions = try? await audioTrack.load(.formatDescriptions)
            if let desc = formatDescriptions?.first {
                let codecType = CMFormatDescriptionGetMediaSubType(desc)
                audioCodecName = mapAudioCodecType(codecType)

                // Check for Atmos (E-AC3 with JOC)
                if codecType == kAudioFormatEnhancedAC3 {
                    if let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] {
                        isDolbyAtmos = checkDolbyAtmos(extensions)
                    }
                    if !isDolbyAtmos {
                        isDolbyAtmos = true // E-AC3 may carry Atmos
                    }
                }
            }
        }

        let duration = try? await asset.load(.duration)
        let durationSeconds = duration?.seconds ?? 0

        // Non-native containers with compatible codecs can be remuxed
        if !isAVPlayerCompatible && videoCodec != .unknown {
            let compatibleVideoCodecs: Set<VideoCodec> = [.h264, .hevc, .av1, .prores]
            if compatibleVideoCodecs.contains(videoCodec) {
                isAVPlayerCompatible = true
            }
        }

        return MediaInfo(
            url: url,
            videoCodec: videoCodec,
            audioCodecName: audioCodecName,
            hdrType: hdrType,
            isDolbyVision: isDolbyVision,
            isDolbyAtmos: isDolbyAtmos,
            videoSize: videoSize,
            duration: durationSeconds,
            bitrate: nil,
            isAVPlayerCompatible: isAVPlayerCompatible
        )
    }

    private static func mapCodecType(_ type: FourCharCode) -> VideoCodec {
        switch type {
        case kCMVideoCodecType_H264:
            return .h264
        case kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha:
            return .hevc
        case kCMVideoCodecType_VP9:
            return .vp9
        default:
            let fourCC = String(format: "%c%c%c%c",
                                (type >> 24) & 0xFF,
                                (type >> 16) & 0xFF,
                                (type >> 8) & 0xFF,
                                type & 0xFF)
            if fourCC.contains("av01") || fourCC.contains("AV1") {
                return .av1
            }
            if fourCC.contains("apch") || fourCC.contains("apcn") || fourCC.contains("apcs") {
                return .prores
            }
            return .unknown
        }
    }

    private static func isCodecAVPlayerCompatible(_ type: FourCharCode) -> Bool {
        let compatible: Set<FourCharCode> = [
            kCMVideoCodecType_H264,
            kCMVideoCodecType_HEVC,
            kCMVideoCodecType_HEVCWithAlpha,
            kCMVideoCodecType_VP9,
        ]
        return compatible.contains(type)
    }

    private static func mapAudioCodecType(_ type: FourCharCode) -> String {
        switch type {
        case kAudioFormatMPEG4AAC: return "AAC"
        case kAudioFormatAC3: return "AC3"
        case kAudioFormatEnhancedAC3: return "E-AC3"
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatLinearPCM: return "PCM"
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatFLAC: return "FLAC"
        case kAudioFormatOpus: return "Opus"
        default: return "Audio"
        }
    }

    private static func checkDolbyVision(_ extensions: [String: Any]) -> Bool {
        // Check for Dolby Vision configuration record
        if let sampleDescExtensions = extensions["SampleDescriptionExtensionAtoms"] as? [String: Any] {
            // dvcC = DV configuration box (Profile 7/8)
            // dvvC = DV configuration box (Profile 5)
            if sampleDescExtensions["dvcC"] != nil || sampleDescExtensions["dvvC"] != nil {
                return true
            }
        }

        return false
    }

    private static func detectHDRType(_ extensions: [String: Any]) -> HDRType {
        guard let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String else {
            return .sdr
        }

        if transfer.contains("SMPTE_ST_2084") || transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) {
            return .hdr10
        }

        if transfer.contains("ITU_R_2100_HLG") || transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) {
            return .hlg
        }

        return .sdr
    }

    private static func checkDolbyAtmos(_ extensions: [String: Any]) -> Bool {
        // E-AC3 with JOC (Joint Object Coding) is Dolby Atmos
        if let sampleDescExtensions = extensions["SampleDescriptionExtensionAtoms"] as? [String: Any] {
            if sampleDescExtensions["dec3"] != nil {
                return true
            }
        }
        return false
    }
}
