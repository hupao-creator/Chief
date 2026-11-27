import AVFoundation
import Dispatch
import Synchronization
@preconcurrency import LiveKitWebRTC

/// Reads the negotiated remote track just before playout. Only a timestamp
/// crosses WebRTC's audio thread; PCM is neither retained nor sent to the UI.
final class VoicePlaybackActivity: NSObject, LKRTCAudioRenderer {
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
