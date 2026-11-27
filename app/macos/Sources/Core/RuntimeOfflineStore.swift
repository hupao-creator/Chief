import CryptoKit
import Darwin
import Foundation

/// Device-owned reading bytes. This directory is separate from drafts and the
/// command journal: evicting old reading content can never remove unsent work.
struct RuntimeOfflineStore: Sendable {
    static let maximumBytes = 64 * 1024 * 1024
    static let maximumEntries = 128
    let directory: URL
    let hostID: String

    init(storageDirectory: URL, hostID: String?) {
        directory = storageDirectory.appendingPathComponent("client-reading-cache", isDirectory: true)
        self.hostID = hostID ?? "local"
    }

    func state() -> JSONValue? {
        guard let value = read("state") else { return nil }
        return try? RuntimeState.admittingSnapshot(value)
    }

    func content(thread: JSONText, scope: RuntimeContentScope) -> JSONValue? {
        read(contentKey(thread: thread, scope: scope))
    }

    func saveState(_ value: JSONValue) throws { try write(value, key: "state") }
    func saveContent(_ value: JSONValue, thread: JSONText, scope: RuntimeContentScope) throws {
        try write(value, key: contentKey(thread: thread, scope: scope))
    }

    private func contentKey(thread: JSONText, scope: RuntimeContentScope) -> String {
        let key = runtimeObject(["thread": .string(thread), "scope": scope.json])
        return "content-" + RuntimePrivateFile.key((try? key.encodedData()) ?? Data())
    }

    private func read(_ key: String) -> JSONValue? {
        let file = directory.appendingPathComponent(key + ".json")
        guard let data = try? RuntimePrivateFile.read(file, maximumBytes: RuntimeProtocol.maxResponseBytes + 1024),
              let document = try? JSONValue(data: data), document["version"]?.intValue == 1,
              document["hostID"]?.stringValue == hostID, let value = document["value"] else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return value
    }

    private func write(_ value: JSONValue, key: String) throws {
        let data = try runtimeObject(["version": .integer(1), "hostID": .text(hostID), "value": value]).encodedData()
        guard data.count <= RuntimeProtocol.maxResponseBytes + 1024 else { return }
        let file = directory.appendingPathComponent(key + ".json")
        try RuntimePrivateFile.write(data, to: file)
        try trim(keeping: file)
    }

    private func trim(keeping protected: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
        var entries: [(URL, Int, Date)] = []
        for file in files where file.pathExtension == "json" {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            entries.append((file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast))
        }
        var bytes = entries.reduce(0) { $0 + $1.1 }
        var count = entries.count
        for entry in entries.sorted(by: { $0.2 < $1.2 }) where entry.0 != protected {
            guard bytes > Self.maximumBytes || count > Self.maximumEntries else { break }
            try FileManager.default.removeItem(at: entry.0)
            bytes -= entry.1; count -= 1
        }
    }
}

/// A draft is durable user input, never part of the evictable reading cache.
/// The caller supplies a host-specific directory and an opaque surface identity.
public struct RuntimeDraftStore: Sendable {
    private let file: URL
    private let scope: JSONText
    private let storageDirectory: URL

    public struct Retained: Sendable {
        public let value: JSONValue?
        public let attachmentIDs: [JSONText]
        public let owner: RuntimeAttachmentOwner
    }

    public init(storageDirectory: URL, scope: JSONText) {
        self.scope = scope
        self.storageDirectory = storageDirectory
        let encoded = (try? JSONValue.string(scope).encodedData()) ?? Data()
        file = storageDirectory.appendingPathComponent("client-drafts", isDirectory: true)
            .appendingPathComponent(RuntimePrivateFile.key(encoded) + ".json")
    }

    public func load() throws -> JSONValue? {
        try RuntimeAttachmentLease.withSharedOwnership(in: storageDirectory) { try readDocument(readEnvelope())?.value }
    }

    /// Read and pin under the same gate so another client's replacement of the
    /// saved draft cannot let collection overtake this restored in-memory owner.
    public func loadRetainingAttachments() throws -> Retained {
        try RuntimeAttachmentLease.withSharedOwnership(in: storageDirectory) {
            let document = try readDocument(readEnvelope())
            let ids = document?.attachmentIDs ?? []
            let owner = try RuntimeAttachmentLease.ownerWhileLocked(in: storageDirectory, attachmentIDs: ids)
            return Retained(value: document?.value, attachmentIDs: ids, owner: owner)
        }
    }

    public static func retainAttachments(_ attachmentIDs: [JSONText], storageDirectory: URL) throws -> RuntimeAttachmentOwner {
        try RuntimeAttachmentLease.withSharedOwnership(in: storageDirectory) {
            try RuntimeAttachmentLease.ownerWhileLocked(in: storageDirectory, attachmentIDs: attachmentIDs)
        }
    }

    private struct Document {
        let value: JSONValue
        let attachmentIDs: [JSONText]
        let move: Move?
    }

    private enum Move: Equatable {
        case outgoing(UUID, to: JSONText)
        case incoming(UUID, from: JSONText)

        static let key: JSONText = "nativeDraftScopeMove"
        var json: JSONValue {
            switch self {
            case let .outgoing(id, target): .object(["id": .text(id.uuidString), "to": .string(target)])
            case let .incoming(id, source): .object(["id": .text(id.uuidString), "from": .string(source)])
            }
        }

        init(_ value: JSONValue, scope: JSONText) throws {
            guard let fields = value.objectValue, fields.count == 2,
                  let id = fields["id"]?.stringValue.flatMap(UUID.init(uuidString:)) else {
                throw RuntimeError("DRAFT_STORAGE_INVALID", "The saved draft move could not be read")
            }
            if case let .string(target) = fields["to"], target != scope { self = .outgoing(id, to: target) }
            else if case let .string(source) = fields["from"], source != scope { self = .incoming(id, from: source) }
            else { throw RuntimeError("DRAFT_STORAGE_INVALID", "The saved draft move has an invalid scope") }
        }
    }

    private func readEnvelope() throws -> Document? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try RuntimePrivateFile.read(file, maximumBytes: RuntimeProtocol.maxRequestBytes)
        let document = try JSONValue(data: data)
        guard document["version"]?.intValue == 2, document["scope"] == .string(scope),
              let attachmentIDs = document["attachmentIDs"]?.arrayValue,
              let value = document["value"] else {
            throw RuntimeError("DRAFT_STORAGE_INVALID", "The saved draft could not be read")
        }
        let ids = try attachmentIDs.map { item -> JSONText in
            guard case let .string(id) = item else { throw RuntimeError("DRAFT_STORAGE_INVALID", "Invalid saved draft attachment") }
            return id
        }
        if var fields = value.objectValue, let marker = fields.removeValue(forKey: Move.key) {
            return Document(value: .object(fields), attachmentIDs: ids, move: try Move(marker, scope: scope))
        }
        return Document(value: value, attachmentIDs: ids, move: nil)
    }

    private func readDocument(_ envelope: Document?) throws -> Document? {
        if case let .outgoing(id, target) = envelope?.move {
            let destination = RuntimeDraftStore(storageDirectory: storageDirectory, scope: target)
            if try destination.readEnvelope()?.move == .incoming(id, from: scope) { return nil }
        }
        return envelope
    }

    /// Match and replace under the collector's gate so another client cannot
    /// erase a pending send or consume a newer draft between read and write.
    public func update(_ change: (JSONValue?) throws -> (JSONValue, [JSONText])?) throws {
        try RuntimeAttachmentLease.withExclusiveOwnership(in: storageDirectory) {
            let current = try readEnvelope()
            if let (value, ids) = try change(readDocument(current)?.value) {
                try write(value, attachmentIDs: ids, replacing: current)
            }
        }
    }

    public func save(_ value: JSONValue, attachmentIDs: [JSONText] = []) throws {
        try RuntimeAttachmentLease.withExclusiveOwnership(in: storageDirectory) {
            try write(value, attachmentIDs: attachmentIDs, replacing: readEnvelope())
        }
    }

    /// Both scopes use the same attachment-ownership gate. The destination's
    /// atomic write commits the move. If the process exits before unlinking
    /// the source, its matching marker still makes it logically empty.
    public func move<Result>(to destination: Self,
                             merging: (JSONValue, JSONValue?) throws -> (value: JSONValue, attachmentIDs: [JSONText], result: Result)) throws -> (result: Result, owner: RuntimeAttachmentOwner) {
        guard storageDirectory == destination.storageDirectory, file != destination.file else {
            throw RuntimeError("DRAFT_STORAGE_INVALID", "A draft move requires two scopes in the same profile")
        }
        // On a failed disk write, release the new owner's token after leaving
        // the exclusive gate. Its destructor acquires the shared gate.
        var pinned: RuntimeAttachmentOwner?
        defer { withExtendedLifetime(pinned) {} }
        return try RuntimeAttachmentLease.withExclusiveOwnership(in: storageDirectory) {
            let before = try readEnvelope(), after = try destination.readEnvelope()
            guard let source = try readDocument(before) else {
                throw RuntimeError("DRAFT_CHANGED", "The source draft changed before it could be moved")
            }
            let merged = try merging(source.value, destination.readDocument(after)?.value)
            let owner = try RuntimeAttachmentLease.ownerWhileLocked(in: storageDirectory, attachmentIDs: merged.attachmentIDs)
            pinned = owner
            let id = UUID()
            try write(source.value, attachmentIDs: source.attachmentIDs, replacing: before, move: .outgoing(id, to: destination.scope))
            try destination.write(merged.value, attachmentIDs: merged.attachmentIDs, replacing: after, move: .incoming(id, from: scope))
            // A failed unlink is retried before the destination replaces its
            // receipt. Until then both the reader and collector retain safety.
            try? FileManager.default.removeItem(at: file)
            return (merged.result, owner)
        }
    }

    public func acquireSubmissionLease() throws -> RuntimeDraftSubmissionLease {
        try RuntimeDraftSubmissionLease(file: file.deletingPathExtension().appendingPathExtension("lock"))
    }

    private func write(_ value: JSONValue, attachmentIDs: [JSONText], replacing current: Document?, move: Move? = nil) throws {
        // Runtime collectors strictly decode the v2 envelope. Only the opaque
        // native value carries the optional, crash-recoverable scope move.
        var stored = value
        if let move {
            guard var fields = value.objectValue else { throw RuntimeError("DRAFT_STORAGE_INVALID", "Invalid draft move contents") }
            fields[Move.key] = move.json
            stored = .object(fields)
        }
        let data = try runtimeObject(["version": .integer(2), "scope": .string(scope),
            "attachmentIDs": .array(attachmentIDs.map(JSONValue.string)), "value": stored]).encodedData()
        guard data.count <= RuntimeProtocol.maxRequestBytes else { throw RuntimeError("DRAFT_TOO_LARGE", "The draft exceeds the local storage limit") }
        if case let .incoming(id, previous) = current?.move {
            let source = RuntimeDraftStore(storageDirectory: storageDirectory, scope: previous)
            if try source.readEnvelope()?.move == .outgoing(id, to: scope) {
                try FileManager.default.removeItem(at: source.file)
            }
        }
        try RuntimePrivateFile.write(data, to: file)
    }
}

/// Held from before the draft handoff through receipt consumption. Process exit
/// releases the kernel lock, allowing another owner to review the saved input.
public final class RuntimeDraftSubmissionLease {
    private let descriptor: Int32
    fileprivate init(file: URL) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw RuntimeError("DRAFT_IO", "Could not open the draft directory") }
        defer { Darwin.close(fd) }
        descriptor = try RuntimeProfileClientLease.lockFile(directory: fd, name: file.lastPathComponent,
            mode: LOCK_EX, busy: RuntimeError("DRAFT_SENDING", "The original send is still in progress."))
    }
    deinit { Darwin.close(descriptor) }
}

enum RuntimePrivateFile {
    static func key(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func read(_ file: URL, maximumBytes: Int) throws -> Data {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= maximumBytes else {
            throw RuntimeError("CLIENT_STORAGE_INVALID", "Client storage is invalid or exceeds its size limit")
        }
        let data = try Data(contentsOf: file)
        guard data.count <= maximumBytes else { throw RuntimeError("CLIENT_STORAGE_INVALID", "Client storage exceeds its size limit") }
        return data
    }

    static func write(_ data: Data, to file: URL) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw RuntimeError("CLIENT_STORAGE_INVALID", "Client storage must be a private directory")
        }
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: attributes) else {
            throw RuntimeError("CLIENT_STORAGE_INVALID", "Could not create a private client record")
        }
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        guard rename(temporary.path, file.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let descriptor = open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
