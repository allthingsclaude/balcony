import AVFoundation
import os

/// Plays short synthesized tones for voice recording start/stop feedback.
/// Uses its own audio engine (output only) separate from the mic engine.
@MainActor
final class SoundEffect {
    static let shared = SoundEffect()

    private let logger = Logger(subsystem: "com.balcony.mac", category: "SoundEffect")
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let dingBuffer: AVAudioPCMBuffer
    private let dongBuffer: AVAudioPCMBuffer

    private init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

        // Ding: bright, short — C6 (1047 Hz), 80ms
        dingBuffer = Self.synthesizeTone(
            frequency: 1047,
            duration: 0.08,
            volume: 0.12,
            format: format
        )

        // Dong: warm, slightly longer — G4 (392 Hz), 120ms
        dongBuffer = Self.synthesizeTone(
            frequency: 392,
            duration: 0.12,
            volume: 0.12,
            format: format
        )

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func playDing() { play(dingBuffer) }
    func playDong() { play(dongBuffer) }

    // MARK: - Private

    private func play(_ buffer: AVAudioPCMBuffer) {
        do {
            if !engine.isRunning { try engine.start() }
            player.play()
            player.scheduleBuffer(buffer, completionHandler: nil)
        } catch {
            logger.error("Failed to play sound: \(error.localizedDescription)")
        }
    }

    /// Synthesize a short tone with gentle attack/decay and a warm second harmonic.
    private static func synthesizeTone(
        frequency: Double,
        duration: Double,
        volume: Float,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = Int(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let data = buffer.floatChannelData![0]
        let attackSamples = Int(sampleRate * 0.005) // 5ms attack ramp

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate

            // Envelope: quick attack ramp + exponential decay
            let attack = min(Double(i) / Double(attackSamples), 1.0)
            let decay = exp(-t * 25)
            let envelope = attack * decay

            // Fundamental + second harmonic at 1/3 volume for warmth
            let fundamental = sin(2 * .pi * frequency * t)
            let harmonic = sin(2 * .pi * frequency * 2 * t) * 0.3
            let sample = (fundamental + harmonic) * envelope * Double(volume)

            data[i] = Float(sample)
        }

        return buffer
    }
}
