import AVFoundation
import CoreAudio
import Foundation
@preconcurrency import LiveKitWebRTC

/// All native handles and pending SDP completions belong to this one attempt.
@MainActor
final class VoiceMedia {
    private static let sslReady = LKRTCInitializeSSL()
    private var factory: LKRTCPeerConnectionFactory?
    private var peer: LKRTCPeerConnection?
    private var channel: LKRTCDataChannel?
    private var track: LKRTCAudioTrack?
    private var sender: LKRTCRtpSender?
    private var remoteTrack: LKRTCAudioTrack?
    private let playback = VoicePlaybackActivity()
    private var pending: (() -> Void)?
    private var health: Task<Void, Never>?
    private var metering: Task<Void, Never>?
    private var muted = false
    private var closed = false
    var onFailure: (() -> Void)?
    var onRemoteSpeaking: ((Bool) -> Void)?
    private(set) var isRemoteSpeaking = false
    private(set) var failure: String?

    func offer() async throws -> String {
        try checkOpen()
        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        if permission == .notDetermined {
            let allowed: Bool = try await operation("Microphone access was not confirmed.", timeout: nil) { finish in
                AVCaptureDevice.requestAccess(for: .audio) { finish(.success($0)) }
            }
            guard allowed else { throw VoiceFailure(Self.permissionMessage) }
        } else if permission != .authorized { throw VoiceFailure(Self.permissionMessage) }
        try checkOpen()
        guard Self.sslReady, Self.deviceAvailable(input: true), Self.deviceAvailable(input: false) else {
            throw VoiceFailure("Voice Mode needs an available microphone and audio output.")
        }
        let factory = LKRTCPeerConnectionFactory(audioDeviceModuleType: .audioEngine, bypassVoiceProcessing: false,
                                                 encoderFactory: nil, decoderFactory: nil, audioProcessingModule: nil)
        self.factory = factory
        // Apple's duplex Voice Processing I/O couples input to output. WebRTC's
        // software echo cancellation lets the system output run on its own.
        guard factory.audioDeviceModule.setPlatformVoiceProcessingAllowed(false) == 0 else {
            throw VoiceFailure("Could not configure independent microphone and speaker I/O.")
        }
        // Negotiate the track with both hardware gates shut until the sideband
        // has confirmed the remote session and the media channel is connected.
        try setAudio(input: false, output: false)
        let config = LKRTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        let empty = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peer = factory.peerConnection(with: config, constraints: empty, delegate: nil) else {
            throw VoiceFailure("Could not create a voice connection.")
        }
        self.peer = peer
        let track = factory.audioTrack(with: factory.audioSource(with: empty), trackId: "chief-microphone")
        guard track.setAudioProcessingOptions(.communication()).isSuccess else {
            throw VoiceFailure("Could not configure voice echo cancellation.")
        }
        self.track = track
        track.isEnabled = false
        let channelConfig = LKRTCDataChannelConfiguration()
        channelConfig.isOrdered = true
        guard let sender = peer.add(track, streamIds: ["chief-voice"]),
              let channel = peer.dataChannel(forLabel: "oai-events", configuration: channelConfig) else {
            throw VoiceFailure("Could not create the voice track and data channel.")
        }
        self.sender = sender
        self.channel = channel
        let offer: String = try await operation("Could not generate a voice offer.") { finish in
            peer.offer(for: LKRTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"], optionalConstraints: nil)) { sdp, err in
                if let sdp { finish(.success(sdp.sdp)) }
                else { finish(.failure(VoiceFailure(err?.localizedDescription ?? "Missing voice offer."))) }
            }
        }
        try await setDescription(offer, remote: false)
        try await wait("Voice network discovery timed out.") { peer.iceGatheringState == .complete }
        guard let sdp = peer.localDescription?.sdp, !sdp.isEmpty, sdp.utf8.count <= 128000 else {
            throw VoiceFailure("Invalid local voice offer.")
        }
        return sdp
    }

    func connect(answer: String) async throws {
        try checkOpen()
        guard let peer, let channel, let adm = factory?.audioDeviceModule else { throw CancellationError() }
        try await setDescription(answer, remote: true)
        try await wait("The voice media connection timed out.") { peer.connectionState == .connected && channel.readyState == .open }
        guard let remote = peer.receivers.compactMap({ $0.track as? LKRTCAudioTrack }).first else {
            throw VoiceFailure("The voice connection did not provide a remote audio track.")
        }
        remoteTrack = remote
        remote.add(playback)
        try setAudio(input: true, output: true)
        track?.isEnabled = true
        try await wait("Could not start the microphone or speaker.") { adm.isRecording && adm.isPlaying && adm.isEngineRunning }
        metering = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
                guard let self, !self.closed else { return }
                let speaking = self.playback.isAudible
                if speaking != self.isRemoteSpeaking {
                    self.isRemoteSpeaking = speaking
                    self.onRemoteSpeaking?(speaking)
                }
            }
        }
        health = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self, !self.closed else { return }
                guard peer.connectionState == .connected, channel.readyState == .open,
                      Self.deviceAvailable(input: false), adm.isPlaying, adm.isEngineRunning,
                      self.muted ? !adm.isRecording : (adm.isRecording && Self.deviceAvailable(input: true)) else {
                    self.fail("The voice connection or audio device disconnected.")
                    return
                }
            }
        }
    }

    private static let permissionMessage = "Allow Chief to use the microphone in System Settings → Privacy & Security → Microphone."
    func setMicrophoneMuted(_ muted: Bool) throws {
        try checkOpen()
        guard self.muted != muted else { return }
        guard let adm = factory?.audioDeviceModule, let sender, let track else { throw CancellationError() }
        if muted {
            // Keep the negotiated transceiver and receiver alive while removing the microphone source.
            track.isEnabled = false
            sender.track = nil
            try setAudio(input: false, output: true)
            guard sender.track == nil, !adm.isRecording || adm.stopRecording() == 0, !adm.isRecording else {
                throw VoiceFailure("Could not release the microphone.")
            }
        } else {
            guard Self.deviceAvailable(input: true) else { throw VoiceFailure("The microphone is unavailable.") }
            try setAudio(input: true, output: true)
            sender.track = track
            guard sender.track?.trackId == track.trackId,
                  adm.isRecording || adm.initAndStartRecording() == 0, adm.isRecording else {
                throw VoiceFailure("Could not restart the microphone.")
            }
            track.isEnabled = true
        }
        self.muted = muted
    }

    private func setAudio(input: Bool, output: Bool) throws {
        guard let adm = factory?.audioDeviceModule,
              adm.setEngineAvailability(LKRTCAudioEngineAvailability(isInputAvailable: ObjCBool(input),
                                                                     isOutputAvailable: ObjCBool(output))) == 0 else {
            throw VoiceFailure("Could not change microphone and speaker availability.")
        }
    }

    func fail(_ message: String) {
        guard !closed else { return }
        failure = message
        let notify = onFailure
        close()
        notify?()
    }

    private func setDescription(_ sdp: String, remote: Bool) async throws {
        try checkOpen()
        guard let peer else { throw CancellationError() }
        let _: Bool = try await operation("Voice negotiation timed out.") { finish in
            let completion: @Sendable (Error?) -> Void = { error in
                if let error { finish(.failure(VoiceFailure(error.localizedDescription))) } else { finish(.success(true)) }
            }
            let desc = LKRTCSessionDescription(type: remote ? .answer : .offer, sdp: sdp)
            if remote { peer.setRemoteDescription(desc, completionHandler: completion) }
            else { peer.setLocalDescription(desc, completionHandler: completion) }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        health?.cancel(); health = nil
        metering?.cancel(); metering = nil
        remoteTrack?.remove(playback); remoteTrack = nil
        isRemoteSpeaking = false
        onRemoteSpeaking = nil
        pending?(); pending = nil
        track?.isEnabled = false
        sender?.track = nil; sender = nil
        try? setAudio(input: false, output: false)
        channel?.close(); channel = nil
        peer?.close(); peer = nil
        _ = factory?.audioDeviceModule.stopRecording()
        _ = factory?.audioDeviceModule.stopPlayout()
        track = nil; factory = nil
        onFailure = nil
    }

    private func checkOpen() throws {
        try Task.checkCancellation()
        if closed { throw CancellationError() }
    }
    private func wait(_ message: String, ready: () -> Bool) async throws {
        let until = ContinuousClock.now.advanced(by: .seconds(20))
        while true {
            try checkOpen()
            if ready() { return }
            guard ContinuousClock.now < until else { throw VoiceFailure(message) }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
    private func operation<T: Sendable>(_ message: String, timeout: Duration? = .seconds(20),
        start: (@escaping @Sendable (Result<T, VoiceFailure>) -> Void) -> Void) async throws -> T {
        try checkOpen()
        defer { pending = nil }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let gate = VoiceCompletion(continuation)
                pending = { gate.finish(.failure(CancellationError())) }
                if let timeout {
                    gate.timeout = Task {
                        do { try await Task.sleep(for: timeout) } catch { return }
                        gate.finish(.failure(VoiceFailure(message)))
                    }
                }
                start { result in Task { @MainActor in gate.finish(result.mapError { $0 as Error }) } }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.close() }
        }
    }
    private static func deviceAvailable(input: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return false }
        address.mSelector = kAudioDevicePropertyDeviceIsAlive
        var alive: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &alive) == noErr && alive != 0
    }
}

struct VoiceFailure: LocalizedError, Sendable {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

@MainActor
private final class VoiceCompletion<T: Sendable> {
    private var continuation: CheckedContinuation<T, Error>?
    var timeout: Task<Void, Never>?
    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }
    func finish(_ result: Result<T, Error>) {
        guard let continuation else { return }
        self.continuation = nil; timeout?.cancel(); timeout = nil
        continuation.resume(with: result)
    }
}
