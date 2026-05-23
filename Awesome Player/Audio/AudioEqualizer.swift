/// 10-band parametric equalizer wrapping AVAudioUnitEQ. Uses standard ISO center
/// frequencies (32 Hz - 16 kHz) that match most hardware/software EQ implementations.
/// Presets store gain values in dB per band; bandwidth of 1.0 octave per band gives
/// smooth overlap between adjacent bands without gaps or excessive peaking.
import AVFoundation

struct EQPreset {
    let name: String
    let gains: [Float] // 10 bands, values in dB
}

class AudioEqualizer {
    let node: AVAudioUnitEQ

    static let bandFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    static let presets: [EQPreset] = [
        EQPreset(name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Bass Boost", gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Treble Boost", gains: [0, 0, 0, 0, 0, 0, 2, 4, 5, 6]),
        EQPreset(name: "Vocal", gains: [-2, -1, 0, 2, 4, 4, 2, 0, -1, -2]),
        EQPreset(name: "Rock", gains: [4, 3, 0, -2, -1, 1, 3, 4, 4, 4]),
        EQPreset(name: "Jazz", gains: [3, 2, 0, 2, -2, -2, 0, 2, 3, 4]),
        EQPreset(name: "Classical", gains: [4, 3, 2, 1, -1, -1, 0, 2, 3, 4]),
        EQPreset(name: "Electronic", gains: [5, 4, 1, 0, -2, 0, 1, 3, 4, 5]),
    ]

    var preampGain: Float = 0 {
        didSet { node.globalGain = preampGain }
    }

    init() {
        node = AVAudioUnitEQ(numberOfBands: Self.bandFrequencies.count)
        configureBands()
    }

    private func configureBands() {
        for (index, freq) in Self.bandFrequencies.enumerated() {
            let band = node.bands[index]
            band.filterType = .parametric
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
    }

    func applyPreset(_ preset: EQPreset) {
        for (index, gain) in preset.gains.enumerated() {
            guard index < node.bands.count else { break }
            node.bands[index].gain = gain
        }
    }

    func applyPreset(named name: String) {
        if let preset = Self.presets.first(where: { $0.name == name }) {
            applyPreset(preset)
        }
    }

    func setGain(_ gain: Float, forBand band: Int) {
        guard band < node.bands.count else { return }
        node.bands[band].gain = max(-12, min(12, gain))
    }

    func getGain(forBand band: Int) -> Float {
        guard band < node.bands.count else { return 0 }
        return node.bands[band].gain
    }

    func setEnabled(_ enabled: Bool) {
        node.bypass = !enabled
    }

    func reset() {
        applyPreset(Self.presets[0]) // Flat
        preampGain = 0
    }
}
