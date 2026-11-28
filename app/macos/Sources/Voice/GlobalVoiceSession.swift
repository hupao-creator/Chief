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
    private let client: RuntimeClient
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var media: VoiceMedia?
    @ObservationIgnored private var diagnosticTrace: DevDiagnostics.Trace?

    public init(client: RuntimeClient) { self.client = client }

    public func start() {
        guard operation == nil else { return }
        let media = VoiceMedia()
        self.media = media
        media.onRemoteSpeaking = { [weak self, weak media] speaking in
            guard let self, let media, self.media === media, self.state == .listening else { return }
            self.isRemoteSpeaking = speaking
        }
        media.onFailure = { [weak self, weak media] in
            guard let self, let media, self.media === media else { return }
            DevDiagnostics.event("voice.media", "device_or_connection_failed", trace: self.diagnosticTrace)
            self.stop()
        }
        let trace = DevDiagnostics.makeTrace()
        diagnosticTrace = trace
        DevDiagnostics.event("voice.session", "connecting", trace: trace)
        state = .connecting
        operation = Task { [weak self, client] in
            var failure: String?
            do {
                guard await client.connectionStatus() == .connected else {
                    throw VoiceFailure("Connect to the Chief runtime before starting Voice Mode.")
                }
                let offer: String
                do { offer = try await media.offer() }
                catch {
                    if !Task.isCancelled { DevDiagnostics.event("voice.media", "offer_failed", trace: trace) }
                    throw error
                }
                try await DevDiagnostics.$trace.withValue(trace) {
                    try await client.runGlobalVoice(offer: offer) { [weak self] answer in
                        do { try await media.connect(answer: answer) }
                        catch {
                            if !Task.isCancelled { DevDiagnostics.event("voice.media", "negotiation_failed", trace: trace) }
                            throw error
                        }
                        await self?.listening(media)
                    }
                }
            } catch {
                if !Task.isCancelled { failure = error.localizedDescription }
            }
            media.close()
            guard let self, self.media === media else { return }
            self.media = nil
            self.operation = nil
            self.isMicrophoneMuted = false
            self.isRemoteSpeaking = false
            self.state = (media.failure ?? failure).map(State.failed) ?? .idle
            if case .failed = self.state { DevDiagnostics.event("voice.session", "failed", trace: trace) }
            else { DevDiagnostics.event("voice.session", "ended", trace: trace) }
            self.diagnosticTrace = nil
        }
    }

    private func listening(_ media: VoiceMedia) {
        guard self.media === media, state == .connecting else { return }
        isRemoteSpeaking = media.isRemoteSpeaking
        state = .listening
        DevDiagnostics.event("voice.session", "media_ready", trace: diagnosticTrace)
    }

    /// Mute releases the input device and sender. Incoming audio keeps playing.
    public func setMicrophoneMuted(_ muted: Bool) {
        guard state == .listening, let media, isMicrophoneMuted != muted else { return }
        do {
            try media.setMicrophoneMuted(muted)
            isMicrophoneMuted = muted
            DevDiagnostics.event("voice.session", muted ? "microphone_muted" : "microphone_unmuted", trace: diagnosticTrace)
        } catch {
            DevDiagnostics.failure("voice.device_transition", error, trace: diagnosticTrace)
            media.fail(error.localizedDescription)
        }
    }

    /// Releases the microphone synchronously. The stopping state covers the
    /// transport drain and fences a rapid second start. Chief tasks run on.
    public func stop() {
        guard let operation else { return }
        state = .stopping
        DevDiagnostics.event("voice.session", "stopping", trace: diagnosticTrace)
        isMicrophoneMuted = false
        isRemoteSpeaking = false
        media?.close()
        operation.cancel()
    }

    isolated deinit { media?.close(); operation?.cancel() }
}
