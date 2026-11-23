import CryptoKit
import Foundation
import Observation
import ChiefCore
import ChiefPluginAPI

/// One immutable receipt per opened content version. Concurrent clients cannot
/// overwrite another Thread's read state or roll a newer version back.
@MainActor
final class NativeThreadReadHistory {
    @Observable fileprivate final class Entry {
        let version: JSONText
        let url: URL
        var read: Bool
        init(version: JSONText, url: URL) {
            self.version = version; self.url = url
            read = FileManager.default.fileExists(atPath: url.path)
        }
    }

    private let directory: URL
    private var current: [ApplicationThreadRef: Entry] = [:]
    init(profile: URL) { directory = profile.appendingPathComponent("thread-reading", isDirectory: true) }

    func isUnread(_ thread: ApplicationThreadRef, version: JSONText) -> Bool {
        !entry(thread, version: version).read
    }

    func markRead(_ thread: ApplicationThreadRef, version: JSONText) throws {
        let entry = entry(thread, version: version)
        guard !entry.read else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        do { try Data().write(to: entry.url, options: .withoutOverwriting) }
        catch let error as CocoaError where error.code == .fileWriteFileExists { }
        entry.read = true
    }

    private func entry(_ thread: ApplicationThreadRef, version: JSONText) -> Entry {
        if let cached = current[thread], cached.version == version { return cached }
        // Catalog identifiers exclude control characters. Keep them out of file paths.
        let key = [thread.typeID, thread.threadID, version].map(\.string).joined(separator: "\u{0}")
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let entry = Entry(version: version, url: directory.appendingPathComponent(name))
        current[thread] = entry
        return entry
    }
}

extension HarnessThread {
    var bookmarkVersion: JSONText? {
        guard isOrdinaryAgent, let execution = observation.latestExecution,
              execution.status == .completed else { return nil }
        return execution.executionID
    }
}
