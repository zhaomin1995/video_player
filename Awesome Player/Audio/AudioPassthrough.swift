import AVFoundation
import CoreAudio

class AudioPassthrough {
    struct PassthroughCapability {
        let deviceID: AudioDeviceID
        let deviceName: String
        let supportsAC3: Bool
        let supportsEAC3: Bool
        let supportsDTS: Bool
    }

    static func queryOutputDevices() -> [PassthroughCapability] {
        var capabilities: [PassthroughCapability] = []

        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        )
        guard status == noErr else { return capabilities }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        guard status == noErr else { return capabilities }

        for deviceID in deviceIDs {
            if let cap = queryDeviceCapability(deviceID) {
                capabilities.append(cap)
            }
        }

        return capabilities
    }

    private static func queryDeviceCapability(_ deviceID: AudioDeviceID) -> PassthroughCapability? {
        // Get device name
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var nameRef: CFString = "" as CFString
        let nameStatus = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameRef)
        let name = nameStatus == noErr ? nameRef as String : "Unknown"

        // Check output streams for encoded format support
        var streamSize: UInt32 = 0
        var streamAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let streamStatus = AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize)
        guard streamStatus == noErr, streamSize > 0 else { return nil }

        let streamCount = Int(streamSize) / MemoryLayout<AudioStreamID>.size
        var streamIDs = [AudioStreamID](repeating: 0, count: streamCount)
        AudioObjectGetPropertyData(deviceID, &streamAddress, 0, nil, &streamSize, &streamIDs)

        var supportsAC3 = false
        var supportsEAC3 = false
        var supportsDTS = false

        for streamID in streamIDs {
            var formatSize: UInt32 = 0
            var formatAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyAvailablePhysicalFormats,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            let formatStatus = AudioObjectGetPropertyDataSize(streamID, &formatAddress, 0, nil, &formatSize)
            guard formatStatus == noErr else { continue }

            let formatCount = Int(formatSize) / MemoryLayout<AudioStreamRangedDescription>.size
            var formats = [AudioStreamRangedDescription](
                repeating: AudioStreamRangedDescription(),
                count: formatCount
            )
            AudioObjectGetPropertyData(streamID, &formatAddress, 0, nil, &formatSize, &formats)

            for format in formats {
                switch format.mFormat.mFormatID {
                case kAudioFormatAC3:
                    supportsAC3 = true
                case kAudioFormatEnhancedAC3:
                    supportsEAC3 = true
                case kAudioFormat60958AC3:
                    supportsAC3 = true
                default:
                    break
                }
            }
        }

        guard supportsAC3 || supportsEAC3 || supportsDTS else { return nil }

        return PassthroughCapability(
            deviceID: deviceID,
            deviceName: name,
            supportsAC3: supportsAC3,
            supportsEAC3: supportsEAC3,
            supportsDTS: supportsDTS
        )
    }

}
