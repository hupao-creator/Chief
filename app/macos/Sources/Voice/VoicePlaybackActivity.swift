import AVFoundation
import Dispatch
import Synchronization
@preconcurrency import LiveKitWebRTC

/// Accumulate the loudest short window between UI ticks. Each meter has one audio writer.
final class VoiceLevelMeter: Sendable {
    private let peak = Atomic<Int>(0)

    func record(energy: Double, samples: Int) {
        guard samples > 0, energy > Double(samples) * 128 * 128 else { return }
        let rms = sqrt(energy / Double(samples))
        let level = min(1, log10(rms / 128) / 1.8)
        peak.max(Int((level * 100).rounded()), ordering: .relaxed)
    }

    func reset() { peak.store(0, ordering: .relaxed) }

    func takeLevel(after previous: Double) -> Double {
        let sample = Double(peak.exchange(0, ordering: .relaxed)) / 100
        let gain = sample > previous ? 0.85 : 0.35
        let level = previous + (sample - previous) * gain
        return level < 0.01 ? 0 : (level * 100).rounded() / 100
    }
}

/// WebRTC AudioBuffer channels contain Float samples in signed 16-bit amplitude units.
final class VoiceCaptureActivity: NSObject, LKRTCAudioCustomProcessingDelegate {
    let meter = VoiceLevelMeter()

    func audioProcessingInitialize(sampleRate: Int, channels: Int) {}
    func audioProcessingRelease() {}

    func audioProcessingProcess(audioBuffer: LKRTCAudioBuffer) {
        var energy = 0.0
        for channel in 0..<audioBuffer.channels {
            let samples = UnsafeBufferPointer(start: audioBuffer.rawBuffer(forChannel: channel), count: audioBuffer.frames)
            for sample in samples { energy += Double(sample) * Double(sample) }
        }
        meter.record(energy: energy, samples: audioBuffer.channels * audioBuffer.frames)
    }
}

/// Both callbacks discard samples before returning to WebRTC.
final class VoicePlaybackActivity: NSObject, LKRTCAudioRenderer {
    let meter = VoiceLevelMeter()
    private let lastAudible = Atomic<UInt64>(0)

    func render(pcmBuffer: AVAudioPCMBuffer) {
        guard pcmBuffer.format.commonFormat == .pcmFormatInt16 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: pcmBuffer.audioBufferList))
        var count = 0
        var energy: Int64 = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let samples = min(Int(pcmBuffer.frameLength) * Int(buffer.mNumberChannels),
                              Int(buffer.mDataByteSize) / MemoryLayout<Int16>.stride)
            count += samples
            for sample in UnsafeBufferPointer(start: data.assumingMemoryBound(to: Int16.self), count: samples) {
                let value = Int64(sample)
                energy += value * value
            }
        }
        meter.record(energy: Double(energy), samples: count)
        // A per-buffer RMS threshold (~ -48 dBFS) filters codec noise.
        if count > 0 && energy > Int64(count) * 128 * 128 {
            lastAudible.store(DispatchTime.now().uptimeNanoseconds, ordering: .relaxed)
        }
    }

    var isAudible: Bool {
        let last = lastAudible.load(ordering: .relaxed)
        let now = DispatchTime.now().uptimeNanoseconds
        return last > 0 && now - last < 240_000_000
    }
}
