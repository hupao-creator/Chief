import CryptoKit
import Foundation
import OSLog

package enum DevDiagnostics {
    package struct Trace: Sendable {
        let token: String
        let label: String

        fileprivate init() {
            token = UUID().uuidString.lowercased()
            label = SHA256.hash(data: Data(token.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        }
    }

    @TaskLocal package static var trace: Trace?

    private struct Provenance: Decodable { let channel: String }
    private static let enabled: Bool = {
        let bundle = Bundle.main
        guard bundle.bundleURL.pathExtension == "app",
              bundle.bundleIdentifier == "com.mokusei.native.dev",
              let url = bundle.url(forResource: "build-provenance", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let provenance = try? JSONDecoder().decode(Provenance.self, from: data) else { return false }
        return provenance.channel == "development"
    }()
    private static let logger = Logger(subsystem: "com.mokusei.native.dev.diagnostics", category: "native")

    package static func makeTrace() -> Trace? { enabled ? Trace() : nil }

    // Public OSLog fields must be code-owned labels or an ephemeral trace digest.
    package static func event(_ operation: StaticString, _ phase: StaticString, trace: Trace? = Self.trace) {
        guard enabled else { return }
        logger.notice("\(operation, privacy: .public) \(phase, privacy: .public) trace=\(trace?.label ?? "", privacy: .public)")
    }

    package static func failure(_ operation: StaticString, _ error: Error, trace: Trace? = Self.trace) {
        let phase: StaticString
        if error is CancellationError || (error as? URLError)?.code == .cancelled { phase = "canceled" }
        else if (error as? URLError)?.code == .timedOut { phase = "timed_out" }
        else if let error = error as? RuntimeError {
            switch error.kind {
            case .uncertain: phase = "outcome_uncertain"
            case .commandRejected: phase = "command_rejected"
            case .requestRejected: phase = "request_rejected"
            case .protocolFailure:
                switch error.code {
                case "TRANSPORT_TIMEOUT", "STARTUP_TIMEOUT": phase = "timed_out"
                case "STREAM_CLOSED": phase = "stream_closed"
                case "OFFLINE_COMMAND_DISABLED": phase = "offline"
                case "VOICE_ENDED": phase = "remote_ended"
                default: phase = "protocol_failure"
                }
            }
        } else { phase = "failed" }
        event(operation, phase, trace: trace)
    }
}
