@testable import ChiefUI
import AVFAudio
import Observation

/// This session belongs to the demo window. Opening a composer or task never replaces it.
@MainActor @Observable final class VoiceSession {
    private(set) var phase = VoicePhase.idle
    private(set) var awaitingReply = false
    private(set) var microphoneMuted = false

    @ObservationIgnored private var transition: Task<Void, Never>?
    @ObservationIgnored private var playback: AVAudioPlayer?

    var isPlayingReply: Bool { playback?.isPlaying == true }

    func start() {
        guard phase == .idle else { return }
        phase = .connecting
        schedule(after: .milliseconds(250)) { self.phase = .listening }
    }

    func playExample() {
        guard phase == .listening, !awaitingReply else { return }
        awaitingReply = true
        schedule(after: .milliseconds(800)) {
            self.awaitingReply = false
            self.phase = .speaking
            let duration = self.playReply()
            self.schedule(after: .seconds(duration)) { self.finishReply() }
        }
    }

    func interrupt() {
        guard phase == .speaking else { return }
        stopTransition()
        phase = microphoneMuted ? .muted : .listening
    }

    func toggleMute() {
        guard phase != .idle, phase != .connecting else { return }
        microphoneMuted.toggle()
        guard phase != .speaking else { return }
        phase = microphoneMuted ? .muted : .listening
    }

    func end() {
        stopTransition()
        microphoneMuted = false
        phase = .idle
    }

    private func playReply() -> TimeInterval {
        guard let url = Bundle.main.url(forResource: "reply", withExtension: "m4a"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return 4 }
        playback = player
        if ProcessInfo.processInfo.arguments.contains("--replay") { player.volume = 0 }
        return player.play() ? player.duration : 4
    }

    private func finishReply() {
        playback = nil
        phase = microphoneMuted ? .muted : .listening
    }

    private func stopTransition() {
        awaitingReply = false
        transition?.cancel()
        transition = nil
        playback?.stop()
        playback = nil
    }

    private func schedule(after delay: Duration, perform: @escaping @MainActor () -> Void) {
        transition?.cancel()
        transition = Task {
            do { try await Task.sleep(for: delay) } catch { return }
            perform()
        }
    }
}
