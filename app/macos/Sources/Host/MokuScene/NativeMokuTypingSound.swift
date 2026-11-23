import AVFAudio
import ChiefPluginUI
import CoreAudio
import CryptoKit
import Foundation

enum NativeMokuTypingSound {
    private static let queue = DispatchQueue(label: "Chief.keyboard-audio", qos: .userInitiated)
    private static let player = Player()

    static func play(_ key: NativeComposerTypingKey) {
        queue.async { player.play(key) }
    }

    // Only the audio queue accesses the graph, including idle teardown.
    private final class Player: @unchecked Sendable {
        // This suite also searches the global Sound preferences when no suite override exists.
        private let settings = UserDefaults(suiteName: "com.apple.systemsound") ?? .standard
        private lazy var character = load("key_press_click", sha256:
            "6acf08272efa46d9bc6ab58e7d00bc58c7055ceeb0f3d41dc60ea9be74de18bd")
        private lazy var delete = load("key_press_delete", sha256:
            "f3f0064af5fecbf0ad81c42f469a2b6dac97c71ed2ee2273b5cee2df2fa1453f")
        private var engine: AVAudioEngine?
        private let node = AVAudioPlayerNode()
        private var lastKey: UInt64 = 0

        func play(_ key: NativeComposerTypingKey) {
            let enabledKey = "com.apple.sound.uiaudio.enabled"
            guard settings.object(forKey: enabledKey) == nil || settings.bool(forKey: enabledKey) else { return }
            let volumeKey = "com.apple.sound.beep.volume"
            let volume = settings.object(forKey: volumeKey) == nil ? 1 : settings.float(forKey: volumeKey)
            guard volume > 0 else { return }
            let buffer = switch key {
            case .character: character
            case .delete: delete
            }
            guard let buffer, let device = systemOutputDevice() else { return }
            do { try startOutput(on: device, format: buffer.format) } catch { return }
            node.volume = min(1, volume)
            lastKey &+= 1
            let keyNumber = lastKey
            node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                queue.asyncAfter(deadline: .now() + 0.5) {
                    if self.lastKey == keyNumber {
                        self.node.stop()
                        self.engine?.pause()
                    }
                }
            }
            if !node.isPlaying { node.play() }
        }

        private func startOutput(on device: AudioDeviceID, format: AVAudioFormat) throws {
            let engine: AVAudioEngine
            if let existing = self.engine {
                engine = existing
            } else {
                engine = AVAudioEngine()
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: format)
                self.engine = engine
            }
            let output = engine.outputNode.auAudioUnit
            if output.deviceID != device {
                node.stop()
                engine.stop()
                try output.setDeviceID(device)
            }
            if !engine.isRunning { try engine.start() }
        }

        private func systemOutputDevice() -> AudioDeviceID? {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var device = AudioDeviceID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout.size(ofValue: device))
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
                  device != kAudioObjectUnknown else { return nil }
            return device
        }

        private func load(_ name: String, sha256: String) -> AVAudioPCMBuffer? {
            let directory = "/System/iOSSupport/System/Library/PrivateFrameworks/UIKitCore.framework/Resources"
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name).appendingPathExtension("caf")
            guard let data = try? Data(contentsOf: url),
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha256,
                  let file = try? AVAudioFile(forReading: url) else { return nil }
            // Buffered Compose handoffs can deliver several keys in one run-loop turn.
            // Separate adjacent samples even when all of them are scheduled together.
            let gap = AVAudioFrameCount(file.processingFormat.sampleRate * 0.004)
            let capacity = AVAudioFrameCount(file.length) + gap
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity),
                  (try? file.read(into: buffer)) != nil, let samples = buffer.floatChannelData else { return nil }
            samples[0].advanced(by: Int(buffer.frameLength)).initialize(repeating: 0, count: Int(gap))
            buffer.frameLength += gap
            return buffer
        }
    }
}
