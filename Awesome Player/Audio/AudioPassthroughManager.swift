/// Manages audio passthrough (bitstream) for AC3/E-AC3/DTS content.
///
/// Three modes:
///   - Auto: enable passthrough when the audio codec is AC3/E-AC3 AND the output
///     device supports encoded formats (HDMI receiver, optical out, etc.)
///   - Always On: force passthrough whenever a capable device is connected
///   - Off: always decode to PCM
///
/// When passthrough is active, the output device's stream format is switched from
/// PCM to the encoded format so CoreAudio sends the bitstream directly to the
/// receiver. The original format is restored on deactivation.
import Foundation
import CoreAudio
import AVFoundation

protocol AudioPassthroughManagerDelegate: AnyObject {
    func passthroughStateChanged(isActive: Bool, deviceName: String?)
}

class AudioPassthroughManager {
    weak var delegate: AudioPassthroughManagerDelegate?

    private(set) var isPassthroughActive = false
    private(set) var isDeviceCapable = false
    private(set) var capableDeviceName: String?
    private(set) var currentAudioCodec: String?

    private var savedFormat: AudioStreamBasicDescription?
    private var savedStreamID: AudioStreamID = 0
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    enum Mode: Int {
        case auto = 0
        case alwaysOn = 1
        case off = 2
    }

    var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.integer(forKey: Defaults.passthroughMode)) ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Defaults.passthroughMode) }
    }

    init() {
        refreshDeviceCapability()
        startDeviceMonitoring()
    }

    deinit {
        stopDeviceMonitoring()
        deactivate()
    }

    // MARK: - Public API

    /// Call when a new file opens — decides whether to activate passthrough
    func evaluateForMedia(audioCodec: String?) {
        currentAudioCodec = audioCodec
        refreshDeviceCapability()

        switch mode {
        case .auto:
            if isEncodedCodec(audioCodec) && isDeviceCapable {
                activate()
            } else {
                deactivate()
            }
        case .alwaysOn:
            if isDeviceCapable { activate() } else { deactivate() }
        case .off:
            deactivate()
        }
    }

    /// Manual toggle from the menu
    func toggle() {
        if isPassthroughActive {
            deactivate()
        } else if isDeviceCapable {
            activate()
        }
    }

    // MARK: - Codec Detection

    private func isEncodedCodec(_ codec: String?) -> Bool {
        guard let c = codec?.uppercased() else { return false }
        return c == "AC3" || c == "E-AC3" || c == "EAC3" ||
               c == "DTS" || c == "TRUEHD" || c == "ATMOS"
    }

    // MARK: - Device Capability

    func refreshDeviceCapability() {
        let devices = AudioPassthrough.queryOutputDevices()
        isDeviceCapable = !devices.isEmpty
        capableDeviceName = devices.first?.deviceName
    }

    // MARK: - Activate / Deactivate

    private func activate() {
        guard !isPassthroughActive else { return }

        let devices = AudioPassthrough.queryOutputDevices()
        guard let device = devices.first else { return }

        if configureDeviceForEncoded(device) {
            isPassthroughActive = true
            print("[Passthrough] Activated on \(device.deviceName)")
            delegate?.passthroughStateChanged(isActive: true, deviceName: device.deviceName)
        }
    }

    private func deactivate() {
        guard isPassthroughActive else { return }
        restoreDeviceFormat()
        isPassthroughActive = false
        print("[Passthrough] Deactivated")
        delegate?.passthroughStateChanged(isActive: false, deviceName: nil)
    }

    // MARK: - CoreAudio Stream Format

    /// Switches the device's output stream from PCM to an encoded format (AC3/E-AC3).
    /// Saves the original format so it can be restored later.
    private func configureDeviceForEncoded(_ device: AudioPassthrough.PassthroughCapability) -> Bool {
        var streamSize: UInt32 = 0
        var streamAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyDataSize(device.deviceID, &streamAddr, 0, nil, &streamSize) == noErr,
              streamSize > 0 else { return false }

        let count = Int(streamSize) / MemoryLayout<AudioStreamID>.size
        var streamIDs = [AudioStreamID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(device.deviceID, &streamAddr, 0, nil, &streamSize, &streamIDs) == noErr else { return false }

        for streamID in streamIDs {
            // Save current physical format
            var currentFmt = AudioStreamBasicDescription()
            var fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var fmtAddr = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyPhysicalFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            guard AudioObjectGetPropertyData(streamID, &fmtAddr, 0, nil, &fmtSize, &currentFmt) == noErr else { continue }

            // Already in an encoded format — nothing to do
            if currentFmt.mFormatID == kAudioFormatAC3 ||
               currentFmt.mFormatID == kAudioFormatEnhancedAC3 ||
               currentFmt.mFormatID == kAudioFormat60958AC3 {
                savedFormat = currentFmt
                savedStreamID = streamID
                isPassthroughActive = true
                return true
            }

            // Find an encoded format among available physical formats
            guard let encodedFmt = findEncodedFormat(streamID: streamID, preferEAC3: device.supportsEAC3) else { continue }

            var newFmt = encodedFmt
            let status = AudioObjectSetPropertyData(
                streamID, &fmtAddr, 0, nil,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &newFmt
            )

            if status == noErr {
                savedFormat = currentFmt
                savedStreamID = streamID
                return true
            } else {
                print("[Passthrough] Failed to set encoded format: \(status)")
            }
        }

        return false
    }

    private func findEncodedFormat(streamID: AudioStreamID, preferEAC3: Bool) -> AudioStreamBasicDescription? {
        var availSize: UInt32 = 0
        var availAddr = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyAvailablePhysicalFormats,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyDataSize(streamID, &availAddr, 0, nil, &availSize) == noErr else { return nil }

        let count = Int(availSize) / MemoryLayout<AudioStreamRangedDescription>.size
        var formats = [AudioStreamRangedDescription](repeating: AudioStreamRangedDescription(), count: count)
        guard AudioObjectGetPropertyData(streamID, &availAddr, 0, nil, &availSize, &formats) == noErr else { return nil }

        // Prefer E-AC3 if supported, fall back to AC3
        let preferred: [AudioFormatID] = preferEAC3
            ? [kAudioFormatEnhancedAC3, kAudioFormatAC3, kAudioFormat60958AC3]
            : [kAudioFormatAC3, kAudioFormat60958AC3]

        for targetID in preferred {
            if let match = formats.first(where: { $0.mFormat.mFormatID == targetID }) {
                return match.mFormat
            }
        }

        return nil
    }

    private func restoreDeviceFormat() {
        guard savedStreamID != 0, var original = savedFormat else { return }

        var fmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyPhysicalFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectSetPropertyData(
            savedStreamID, &fmtAddr, 0, nil,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &original
        )

        savedStreamID = 0
        savedFormat = nil
    }

    // MARK: - Device Change Monitoring

    private func startDeviceMonitoring() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.handleDeviceChange()
            }
        }
        listenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, DispatchQueue.main, block
        )
    }

    private func stopDeviceMonitoring() {
        guard let block = listenerBlock else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, DispatchQueue.main, block
        )
        listenerBlock = nil
    }

    /// Re-evaluate passthrough when the user switches output devices (e.g. plugs in HDMI)
    private func handleDeviceChange() {
        let wasActive = isPassthroughActive
        refreshDeviceCapability()

        if mode == .auto || mode == .alwaysOn {
            if !isDeviceCapable && wasActive {
                deactivate()
            } else if isDeviceCapable && !wasActive && (mode == .alwaysOn || isEncodedCodec(currentAudioCodec)) {
                activate()
            }
        }
    }
}
