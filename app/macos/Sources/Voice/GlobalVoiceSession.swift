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
    private let client: RuntimeClient
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var media: VoiceMedia?

    public init(client: RuntimeClient) { self.client = client }

    public func start() {
        guard operation == nil else { return }
        let media = VoiceMedia()
        self.media = media
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
            self.state = (media.failure ?? failure).map(State.failed) ?? .idle
        }
        media.onFailure = { [weak self, weak media] in
            guard let self, let media, self.media === media else { return }
            self.stop()
        }
    }

    private func listening(_ media: VoiceMedia) {
        if self.media === media, state == .connecting { state = .listening }
    }

    /// Releases the microphone synchronously. The stopping state covers the
    /// transport drain and fences a rapid second start. Chief tasks run on.
    public func stop() {
        guard let operation else { return }
        state = .stopping
        media?.close()
        operation.cancel()
    }

    isolated deinit { media?.close(); operation?.cancel() }
}

struct VoiceFailure: LocalizedError, Sendable {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
