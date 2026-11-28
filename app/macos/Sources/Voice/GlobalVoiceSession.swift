import ChiefCore
import Foundation
import Observation

/// Retain one session for the workspace. Only an explicit start requests audio
/// access. Navigation and changes to the selected reading Thread have no effect.
@MainActor @Observable
public final class GlobalVoiceSession {
    public enum State: Equatable, Sendable {
        case idle, connecting, listening, stopping
        case failed(String)
    }
    public private(set) var state: State = .idle
    public private(set) var isMicrophoneMuted = false
    public private(set) var isRemoteSpeaking = false
    public private(set) var microphoneLevel = 0.0
    public private(set) var playbackLevel = 0.0
    private let client: RuntimeClient
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var media: VoiceMedia?

    public init(client: RuntimeClient) { self.client = client }

    public func start() {
        guard operation == nil else { return }
        let media = VoiceMedia()
        self.media = media
        media.onLevels = { [weak self, weak media] input, output in
            guard let self, let media, self.media === media, self.state == .listening else { return }
            self.microphoneLevel = input
            self.playbackLevel = output
        }
        media.onRemoteSpeaking = { [weak self, weak media] speaking in
            guard let self, let media, self.media === media, self.state == .listening else { return }
            self.isRemoteSpeaking = speaking
        }
        media.onFailure = { [weak self, weak media] in
            guard let self, let media, self.media === media else { return }
            self.stop()
        }
        state = .connecting
        operation = Task { [weak self, client] in
            var failure: String?
            do {
                guard await client.connectionStatus() == .connected else {
                    throw VoiceFailure("Connect to the Chief runtime before starting Voice Mode.")
                }
                let offer = try await media.offer()
                try await client.runGlobalVoice(offer: offer) { [weak self] answer in
                    try await media.connect(answer: answer)
                    await self?.listening(media)
                }
            } catch {
                if !Task.isCancelled { failure = error.localizedDescription }
            }
            media.close()
            guard let self, self.media === media else { return }
            self.media = nil
            self.operation = nil
            self.isMicrophoneMuted = false
            self.microphoneLevel = 0
            self.playbackLevel = 0
            self.isRemoteSpeaking = false
            self.state = (media.failure ?? failure).map(State.failed) ?? .idle
        }
    }

    private func listening(_ media: VoiceMedia) {
        guard self.media === media, state == .connecting else { return }
        isRemoteSpeaking = media.isRemoteSpeaking
        state = .listening
    }

    /// Mute releases the input device and sender. Incoming audio keeps playing.
    public func setMicrophoneMuted(_ muted: Bool) {
        guard state == .listening, let media, isMicrophoneMuted != muted else { return }
        do {
            try media.setMicrophoneMuted(muted)
            isMicrophoneMuted = muted
        } catch {
            media.fail(error.localizedDescription)
        }
    }

    /// Releases the microphone synchronously. The stopping state covers the
    /// transport drain and fences a rapid second start. Chief tasks run on.
    public func stop() {
        guard let operation else { return }
        state = .stopping
        isMicrophoneMuted = false
        microphoneLevel = 0
        playbackLevel = 0
        isRemoteSpeaking = false
        media?.close()
        operation.cancel()
    }

    isolated deinit { media?.close(); operation?.cancel() }
}
