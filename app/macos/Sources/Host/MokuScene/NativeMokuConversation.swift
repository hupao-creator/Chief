import ChiefCore
import Foundation
import SwiftUI

/// The Dock fits the scroll document and divider before clipping the list above the editor.
struct NativeMokuConversationHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

extension View {
    func reportMokuConversationHeight() -> some View {
        background {
            GeometryReader { bounds in
                Color.clear.preference(key: NativeMokuConversationHeightKey.self, value: bounds.size.height)
            }
        }
    }
}

struct NativeMokuConversationPage {
    struct Message: Identifiable {
        let id: JSONText
        let fromUser: Bool
        let date: Date
        let text: String
        let attachments: [String]
    }
    let messages: [Message]
    let before: JSONText?

    init(_ value: JSONValue) throws {
        let invalid = RuntimeError("INVALID_RESPONSE", "Invalid Chief conversation page")
        guard let rows = value["messages"]?.arrayValue else { throw invalid }
        messages = try rows.map { row in
            guard case .string(let id) = row["id"], let role = row["role"]?.stringValue,
                  role == "user" || role == "chief", let ms = row["createdAt"]?.intValue,
                  let text = row["text"]?.stringValue else { throw invalid }
            let files = try (row["attachments"]?.arrayValue ?? []).map {
                guard let name = $0.stringValue else { throw invalid }
                return name
            }
            return Message(id: id, fromUser: role == "user", date: Date(timeIntervalSince1970: Double(ms) / 1000),
                           text: text, attachments: files)
        }
        if case .string(let cursor) = value["before"] { before = cursor } else { before = nil }
    }
}

/// The page is a live, profile-owned reading resource. The Dock owns the glass
/// and the single native editor below it, including while earlier pages are read.
struct NativeMokuConversation: View {
    let client: RuntimeClient
    let owner: JSONText
    @State private var cursors: [JSONText] = []
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            ConversationMessages(client: client, owner: owner, before: cursors.last, chinese: chinese,
                                 showEarlier: { cursors.append($0) }, showNewer: { _ = cursors.popLast() })
                .id(cursors.last)
            Divider().reportMokuConversationHeight()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(chinese ? "与 Chief 的对话" : "Conversation with Chief")
        .accessibilityIdentifier("moku-conversation")
    }

    private var chinese: Bool { locale.language.languageCode?.identifier == "zh" }
}

private struct ConversationMessages: View {
    let client: RuntimeClient
    let owner: JSONText
    let before: JSONText?
    let chinese: Bool
    let showEarlier: (JSONText) -> Void
    let showNewer: () -> Void
    @State private var page: NativeMokuConversationPage?
    @State private var failure: String?
    @State private var disconnected = false
    @State private var retry = 0

    var body: some View {
        VStack(spacing: 0) {
            if failure == nil, let page, !page.messages.isEmpty {
                NativeMokuConversationTimeline(page: page, showEarlier: showEarlier, showNewer: before == nil ? nil : showNewer)
            } else {
                VStack(spacing: 0) {
                    status
                    if before != nil {
                        // An earlier page can fail independently. Keep the return path available.
                        Button(chinese ? "较新消息" : "Newer messages", action: showNewer)
                            .buttonStyle(.plain).font(.caption).padding(8)
                    }
                }
                .padding(.vertical, 12)
                .fixedSize(horizontal: false, vertical: true)
                .reportMokuConversationHeight()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: retry) { await read() }
    }

    @ViewBuilder private var status: some View {
        if let failure {
            VStack(spacing: 8) {
                Text(chinese ? "无法读取消息" : "Couldn’t load messages").help(failure)
                Button(chinese ? "重试" : "Try again") { retry += 1 }
            }
        } else if page != nil {
            Text(chinese ? "还没有消息" : "No messages yet")
                .font(.callout).foregroundStyle(.secondary)
        } else if disconnected {
            Text(chinese ? "重新连接以读取消息" : "Reconnect to load messages")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func read() async {
        let id = UUID().uuidString
        var events = await client.events()
        failure = nil
        do {
            try await client.subscribeThreadContent(threadId: owner, scope: .mokuConversation(before: before), subscriptionId: id)
            // A slow observer may be retired. Reattaching replays this live
            // resource from the client without starting a second subscription.
            while !Task.isCancelled {
                var overflow = false
                for await event in events {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .threadContent(let received, let state) where received == id:
                        switch state {
                        case .ready(let value): page = try NativeMokuConversationPage(value); failure = nil
                        case .error(let description): failure = description
                        case .loading: break
                        }
                    case .connection(let status): disconnected = status == .disconnected || status == .stopped
                    case .failure(let error) where error.code == "CONSUMER_OVERFLOW": overflow = true
                    default: break
                    }
                }
                guard overflow, !Task.isCancelled else { break }
                events = await client.events()
            }
        } catch {
            if !Task.isCancelled { failure = error.localizedDescription }
        }
        await client.releaseThreadContent(id)
    }
}
