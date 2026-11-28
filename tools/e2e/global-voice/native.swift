import AVFoundation
import CoreAudio
import Foundation
import Synchronization

/// The driver links the production media implementation and accepts SDP only
/// from its parent process over stdio. HAL samples are independent of WebRTC.
@main
@MainActor
struct NativeVoiceProbe {
    struct Request: Decodable {
        let action: String
        let sdp: String?
    }

    static func main() async throws {
        var media: VoiceMedia?
        defer { media?.close() }
        var monitorEngine: AVAudioEngine?
        let room = RoomBands()
        defer { monitorEngine?.stop() }
        for try await line in FileHandle.standardInput.bytes.lines {
            var result: [String: Any] = [:]
            do {
                let request = try JSONDecoder().decode(Request.self, from: Data(line.utf8))
                switch request.action {
                case "preflight":
                    let permission = AVCaptureDevice.authorizationStatus(for: .audio)
                    result["microphonePermission"] = switch permission {
                    case .authorized: "authorized"
                    case .denied: "denied"
                    case .restricted: "restricted"
                    case .notDetermined: "notDetermined"
                    @unknown default: "unknown"
                    }
                    result["defaultInput"] = try defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
                    result["defaultOutput"] = try defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
                case "offer":
                    guard media == nil, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                        throw VoiceFailure("An unused session and existing microphone permission are required.")
                    }
                    let fresh = VoiceMedia()
                    media = fresh
                    result["sdp"] = try await fresh.offer()
                case "answer":
                    guard let media, let sdp = request.sdp else { throw VoiceFailure("Missing media or answer.") }
                    try await media.connect(answer: sdp)
                case "mute", "unmute":
                    guard let media else { throw VoiceFailure("Missing active media.") }
                    try media.setMicrophoneMuted(request.action == "mute")
                case "close":
                    media?.close()
                    media = nil
                case "monitor":
                    guard media == nil, monitorEngine == nil,
                          AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                        throw VoiceFailure("The independent room microphone requires existing permission and idle audio.")
                    }
                    let engine = AVAudioEngine()
                    let node = engine.inputNode
                    let format = node.outputFormat(forBus: 0)
                    guard format.commonFormat == .pcmFormatFloat32, format.sampleRate > 0, format.channelCount > 0 else {
                        throw VoiceFailure("Missing floating-point default microphone input.")
                    }
                    node.installTap(onBus: 0, bufferSize: 1024, format: nil) { @Sendable buffer, _ in room.read(buffer) }
                    monitorEngine = engine
                    try engine.start()
                case "resetBands":
                    room.reset()
                case "bands":
                    let snapshot = room.snapshot()
                    result["power"] = snapshot.power
                    result["buffers"] = snapshot.buffers
                    result["frequenciesHz"] = RoomBands.frequencies
                case "stopMonitor":
                    if let engine = monitorEngine {
                        engine.stop()
                        engine.inputNode.removeTap(onBus: 0)
                        monitorEngine = nil
                    }
                case "state":
                    break
                default:
                    throw VoiceFailure("Unknown native probe action.")
                }
                try result.merge(processIO()) { _, new in new }
                result["speaking"] = media?.isRemoteSpeaking ?? false
                if let failure = media?.failure { result["mediaFailure"] = failure }
            } catch {
                result["error"] = error.localizedDescription
                media?.close()
            }
            let bytes = try JSONSerialization.data(withJSONObject: result)
            try FileHandle.standardOutput.write(contentsOf: bytes + Data([10]))
        }
    }

    private static func property(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                 qualifier: UnsafeRawPointer? = nil, qualifierSize: UInt32 = 0) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        let code = AudioObjectGetPropertyData(object, &address, qualifierSize, qualifier, &size, &value)
        guard code == noErr else { throw VoiceFailure("CoreAudio property \(selector) returned \(code).") }
        return value
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) throws -> UInt32 {
        let device = try property(AudioObjectID(kAudioObjectSystemObject), selector)
        guard device != kAudioObjectUnknown, try property(device, kAudioDevicePropertyDeviceIsAlive) != 0 else { return 0 }
        return device
    }

    private static func processIO() throws -> [String: Any] {
        var pid = getpid()
        let process = try property(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyTranslatePIDToProcessObject,
                                   qualifier: &pid, qualifierSize: UInt32(MemoryLayout<pid_t>.size))
        guard process != kAudioObjectUnknown else {
            // HAL explicitly returns unknown when a PID has no audio client.
            return ["halProcess": 0, "inputRunning": false, "outputRunning": false]
        }
        return ["halProcess": process, "inputRunning": try property(process, kAudioProcessPropertyIsRunningInput) != 0,
                "outputRunning": try property(process, kAudioProcessPropertyIsRunningOutput) != 0]
    }
}

/// Independent acoustic observer. Only narrowband power leaves the tap.
private final class RoomBands: Sendable {
    struct Snapshot: Sendable {
        var power = Array(repeating: 0.0, count: RoomBands.frequencies.count)
        var buffers = 0
    }

    static let frequencies = [650.0, 1_000.0, 1_450.0, 1_900.0, 2_100.0, 2_300.0]
    private let totals = Mutex(Snapshot())

    func reset() { totals.withLock { $0 = Snapshot() } }

    func snapshot() -> Snapshot {
        totals.withLock { state in
            Snapshot(power: state.power.map { $0 / Double(max(1, state.buffers)) }, buffers: state.buffers)
        }
    }

    func read(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        let stride = buffer.stride
        let power = Self.frequencies.map { frequency in
            let coefficient = 2 * cos(2 * .pi * frequency / buffer.format.sampleRate)
            var previous = 0.0, older = 0.0
            for index in 0..<count {
                let current = Double(samples[index * stride]) + coefficient * previous - older
                older = previous
                previous = current
            }
            return 4 * max(0, previous * previous + older * older - coefficient * previous * older)
                / (Double(count) * Double(count))
        }
        totals.withLock { state in
            state.buffers += 1
            for i in power.indices { state.power[i] += power[i] }
        }
    }
}
