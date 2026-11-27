import Foundation

extension RuntimeClient {
    /// The call belongs to this live client/epoch. Ending this task revokes the
    /// media lease, including during SDP negotiation, without a command receipt.
    package func runGlobalVoice(offer: String, answer: @escaping @Sendable (String) async throws -> Void) async throws {
        try assertOpen()
        guard status == .connected, let connection, let clientID else {
            throw RuntimeError("VOICE_OFFLINE", "Connect to the Chief runtime before starting Voice Mode.")
        }
        let body = try JSONEncoder().encode(["clientId": clientID, "offer": offer])
        // Stop can win while the completed offer waits for the client actor.
        try Task.checkCancellation()
        let channel = try RuntimeHTTPChannel(connection: connection, path: "/voice/global", method: "POST",
                                             body: body, timeout: 86400)
        // Keep reading the lease while WebRTC applies SDP and opens its devices.
        // Either failure must also cancel the other side of startup.
        let answers = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [transport] in
                defer { answers.continuation.finish() }
                try await transport.stream(channel) { frame in
                    guard let sdp = frame["answer"]?.stringValue, !sdp.isEmpty, sdp.utf8.count <= 128_000 else {
                        throw RuntimeError("VOICE_ENDED", frame["error"]?["message"]?.stringValue ?? "Invalid voice answer.")
                    }
                    guard case .enqueued = answers.continuation.yield(sdp) else {
                        throw RuntimeError("VOICE_PROTOCOL", "The runtime sent a second voice answer.")
                    }
                    answers.continuation.finish()
                }
            }
            group.addTask {
                for await sdp in answers.stream {
                    try Task.checkCancellation()
                    try await answer(sdp)
                }
            }
            defer { group.cancelAll(); answers.continuation.finish() }
            while let _ = try await group.next() {}
        }
    }
}
