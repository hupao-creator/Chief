import AppKit
import Foundation
import ChiefCore
import ChiefPluginAPI

/// Inspect the captured command and release its receipt after durable draft settlement.
@MainActor public struct NativeComposerReceiptActions {
    public let check: (String) async throws -> RuntimeComposerReceipt
    public let consume: (String) async throws -> Void

    public init(check: @escaping (String) async throws -> RuntimeComposerReceipt, consume: @escaping (String) async throws -> Void) {
        self.check = check
        self.consume = consume
    }
}

/// Capability injection for a particular draft/thread. The composer never owns
/// a general runtime client or chooses another thread's authority.
@MainActor
public struct NativeComposerServices {
    public typealias ChooseItems = (JSONText, PluginLifetime) async throws -> [URL]
    public typealias StageFiles = ([NativeComposerFile], PluginLifetime) async throws -> [NativeComposerStoredAttachment]
    public typealias AttachmentPolicy = (PluginLifetime) async throws -> RuntimeAttachmentPolicy
    public typealias HostDirectory = (RuntimeHostFileReference?, PluginLifetime) async throws -> RuntimeHostDirectory
    public typealias PreviewAttachment = (NativeComposerStoredAttachment, PluginLifetime) async throws -> Data?
    public typealias OpenHostFile = (RuntimeHostFileReference, PluginLifetime) async throws -> Void
    public typealias RetainAttachments = ([JSONText]) throws -> RuntimeAttachmentOwner
    public let receipts: NativeComposerReceiptActions?
    public let chooseItems: ChooseItems
    public let stageFiles: StageFiles
    public let discardAttachments: ([JSONText]) async throws -> Void
    public let attachmentPolicy: AttachmentPolicy?
    public let hostDirectory: HostDirectory?
    public let previewAttachment: PreviewAttachment?
    public let openHostFile: OpenHostFile?
    public let retainAttachments: RetainAttachments?

    public init(chooseItems: ChooseItems? = nil, stageFiles: @escaping StageFiles,
                attachmentPolicy: AttachmentPolicy? = nil, hostDirectory: HostDirectory? = nil,
                previewAttachment: PreviewAttachment? = nil, openHostFile: OpenHostFile? = nil,
                retainAttachments: RetainAttachments? = nil, receipts: NativeComposerReceiptActions? = nil,
                discardAttachments: @escaping ([JSONText]) async throws -> Void) {
        self.receipts = receipts
        self.stageFiles = stageFiles
        self.attachmentPolicy = attachmentPolicy; self.hostDirectory = hostDirectory; self.previewAttachment = previewAttachment
        self.openHostFile = openHostFile
        self.retainAttachments = retainAttachments
        self.discardAttachments = discardAttachments
        self.chooseItems = chooseItems ?? { cwd, lifetime in
            try lifetime.checkCancellation()
            let panel = try Self.devicePicker(cwd: cwd)
            let cancellation = lifetime.onCancel { panel.cancel(nil) }
            defer { lifetime.removeHandler(cancellation) }
            let result = await withCheckedContinuation { continuation in
                if let window = NSApp.keyWindow {
                    panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
                } else {
                    panel.begin { continuation.resume(returning: $0) }
                }
            }
            try lifetime.checkCancellation()
            guard result == .OK else { return [] }
            return panel.urls
        }
    }

    static func devicePicker(cwd: JSONText) throws -> NSOpenPanel {
        // POSIX APIs cannot represent malformed UTF-16 paths. Reject at
        // this explicit native boundary instead of silently repairing one.
        guard Array(cwd.string.utf16) == cwd.codeUnits else {
            throw PluginContractError("The working directory cannot be represented as a native file path")
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        // Set the initial directory on every open so AppKit's remembered
        // location does not override the composer's default.
        panel.directoryURL = cwd.codeUnits.isEmpty
            ? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            : URL(fileURLWithPath: cwd.string, isDirectory: true)
        return panel
    }
}
