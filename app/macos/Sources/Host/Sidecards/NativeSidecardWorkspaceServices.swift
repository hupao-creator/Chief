import Foundation
import ChiefCore
import ChiefPluginAPI
import SwiftUI

/// Runtime authority stays at composition. A workspace only receives commands
/// bound by its owner, and preserves the exact execution identity in each receipt.
@MainActor
public struct NativeSidecardWorkspaceServices {
    public let send: (JSONText, JSONValue) async throws -> SidecardSendReceipt
    public let stageAttachments: ([URL]) async throws -> [SidecardStagedAttachment]
    public let discardAttachments: ([JSONText]) async throws -> Void
    public let openExternal: (JSONText) async throws -> Void
    public let attachmentImport: SidecardAttachmentImport?
    public let compose: (JSONText, JSONText) -> Void
    public let composer: (JSONText, SidecardComposerRequest?) -> Void

    public init(send: @escaping (JSONText, JSONValue) async throws -> SidecardSendReceipt,
                stageAttachments: @escaping ([URL]) async throws -> [SidecardStagedAttachment],
                discardAttachments: @escaping ([JSONText]) async throws -> Void,
                openExternal: @escaping (JSONText) async throws -> Void,
                attachmentImport: SidecardAttachmentImport? = nil,
                compose: @escaping (JSONText, JSONText) -> Void = { _, _ in },
                composer: @escaping (JSONText, SidecardComposerRequest?) -> Void = { _, _ in }) {
        self.send = send; self.stageAttachments = stageAttachments
        self.discardAttachments = discardAttachments; self.openExternal = openExternal
        self.attachmentImport = attachmentImport
        self.compose = compose
        self.composer = composer
    }
}

/// The reading surface needs a conversation, its bound actions and an optional draft store.
@MainActor public protocol NativeThreadReadingHost {
    var draftStorageDirectory: URL? { get }
    func readingActions(for thread: HarnessThread, routes: NativeHarnessThreadRoutes) -> HarnessThreadActions
    func conversation(input: HarnessThreadInput, presentation: HarnessConversationPresentation,
                      routes: NativeHarnessThreadRoutes, onIndexChange: @escaping (ThreadConversationIndex) -> Void) -> AnyView
}

extension NativeHarnessHost: NativeThreadReadingHost {
    public var draftStorageDirectory: URL? { client.storageDirectory }
    public func readingActions(for thread: HarnessThread, routes: NativeHarnessThreadRoutes) -> HarnessThreadActions {
        actions(for: thread, routes: routes)
    }
    public func conversation(input: HarnessThreadInput, presentation: HarnessConversationPresentation,
                             routes: NativeHarnessThreadRoutes, onIndexChange: @escaping (ThreadConversationIndex) -> Void) -> AnyView {
        AnyView(NativeHarnessThreadView(host: self, input: input, presentation: presentation,
                                        routes: routes, onIndexChange: onIndexChange))
    }
}
