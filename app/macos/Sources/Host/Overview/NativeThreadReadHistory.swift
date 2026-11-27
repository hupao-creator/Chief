import CryptoKit
import Darwin
import Foundation
import Observation
import ChiefCore
import ChiefPluginAPI

/// Bookmark receipts are immutable per content version. Foreground visits use
/// a separate history so marking a bookmark as read cannot create a visit.
@MainActor @Observable
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

    private struct Visit: Codable {
        let id: [UInt16]
        let readAt: Double
    }

    private static let recentLimit = 512
    // The profile reset allowlist owns hashed files in this directory. The
    // domains have no NUL separators, unlike the bookmark receipt preimage.
    private static let recentName = fileKey("overview-recent-agent-reads")
    private static let recentLockName = fileKey("overview-recent-agent-reads-lock")
    private let directory: URL
    @ObservationIgnored private var current: [ApplicationThreadRef: Entry] = [:]
    private(set) var recentAgentReads: [JSONText: Double] = [:]

    init(profile: URL) {
        directory = profile.appendingPathComponent("thread-reading", isDirectory: true)
        refreshRecentAgentReads()
    }

    func refreshRecentAgentReads() {
        if let next = try? readRecentAgentReads(), next != recentAgentReads {
            recentAgentReads = next
        }
    }

    func recordRecentAgentRead(_ id: JSONText) throws {
        let readAt = Date.now.timeIntervalSince1970
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let lockURL = directory.appendingPathComponent(Self.recentLockName)
        let fd = open(lockURL.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        var file = stat()
        guard fstat(fd, &file) == 0, (file.st_mode & S_IFMT) == S_IFREG, file.st_uid == getuid() else {
            throw CocoaError(.fileWriteNoPermission)
        }
        // Native clients can share a profile. Merge under a stable lock so
        // another client's read or preference write cannot overwrite a visit.
        let acquire: (Int32, Int32) -> Int32 = flock
        while acquire(fd, LOCK_EX) != 0 {
            if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        var next = try readRecentAgentReads()
        next[id] = max(next[id] ?? 0, readAt)
        if next.count > Self.recentLimit, let oldest = next.min(by: { $0.value < $1.value }) {
            next.removeValue(forKey: oldest.key)
        }
        let visits = next.map { Visit(id: $0.key.codeUnits, readAt: $0.value) }
        try JSONEncoder().encode(visits).write(to: recentURL, options: .atomic)
        recentAgentReads = next
    }

    private var recentURL: URL { directory.appendingPathComponent(Self.recentName) }

    private func readRecentAgentReads() throws -> [JSONText: Double] {
        do {
            let values = try recentURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let data = try Data(contentsOf: recentURL)
            let visits = try JSONDecoder().decode([Visit].self, from: data)
            let newest = visits.filter { !$0.id.isEmpty && $0.readAt.isFinite && $0.readAt >= 0 }
                .sorted { $0.readAt > $1.readAt }.prefix(Self.recentLimit)
            // Preserve UTF-16 wire identity rather than normalizing String keys.
            return Dictionary(newest.map { (JSONText(codeUnits: $0.id), $0.readAt) }, uniquingKeysWith: max)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return [:]
        }
    }

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
        let entry = Entry(version: version, url: directory.appendingPathComponent(Self.fileKey(key)))
        current[thread] = entry
        return entry
    }

    private static func fileKey(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension HarnessThread {
    var bookmarkVersion: JSONText? {
        guard isOrdinaryAgent, let execution = observation.latestExecution,
              execution.status == .completed else { return nil }
        return execution.executionID
    }
}
