import ChiefCore
import Foundation
import SwiftUI

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
    let close: () -> Void
    @State private var cursors: [JSONText] = []
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(chinese ? "与 Chief 的对话" : "Conversation with Chief")
                    .font(.headline)
                Spacer()
                if !cursors.isEmpty {
                    Button(chinese ? "较新消息" : "Newer messages") { cursors.removeLast() }
                        .buttonStyle(.plain).font(.caption)
                }
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24).background(.white.opacity(0.09), in: .circle)
                }.buttonStyle(.plain)
                    .accessibilityLabel(chinese ? "关闭对话" : "Close conversation")
            }.padding(.leading, 20).padding(.trailing, 14).frame(height: 44)
            Divider()
            ConversationMessages(client: client, owner: owner, before: cursors.last, chinese: chinese,
                                 showEarlier: { cursors.append($0) })
                .id(cursors.last)
            Divider()
        }.accessibilityElement(children: .contain).accessibilityIdentifier("moku-conversation")
    }

    private var chinese: Bool { locale.language.languageCode?.identifier == "zh" }
}

private struct ConversationMessages: View {
    let client: RuntimeClient
    let owner: JSONText
    let before: JSONText?
    let chinese: Bool
    let showEarlier: (JSONText) -> Void
    @State private var page: NativeMokuConversationPage?
    @State private var failure: String?
    @State private var disconnected = false
    @State private var retry = 0
    @State private var atBottom = true

    var body: some View {
        Group {
            if let failure {
                VStack(spacing: 8) {
                    Text(chinese ? "无法读取消息" : "Couldn’t load messages").help(failure)
                    Button(chinese ? "重试" : "Try again") { retry += 1 }
                }
            } else if let page {
                if page.messages.isEmpty {
                    Text(chinese ? "还没有消息" : "No messages yet")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    messages(page)
                }
            } else if disconnected {
                Text(chinese ? "重新连接以读取消息" : "Reconnect to load messages")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: retry) { await read() }
    }

    private func messages(_ page: NativeMokuConversationPage) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if let cursor = page.before {
                        Button(chinese ? "较早消息" : "Earlier messages") { showEarlier(cursor) }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(page.messages) { message in
                        bubble(message).id(message.id)
                    }
                }.padding(.vertical, 12).padding(.horizontal, 16)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onScrollGeometryChange(for: Bool.self) { $0.contentSize.height - $0.visibleRect.maxY < 24 } action: { _, nearEnd in
                atBottom = nearEnd
            }
            .onChange(of: page.messages.last?.id) { _, last in
                if atBottom, let last { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    private func bubble(_ message: NativeMokuConversationPage.Message) -> some View {
        let user = message.fromUser
        let speaker = user ? (chinese ? "你" : "You") : "Chief"
        return VStack(alignment: user ? .trailing : .leading, spacing: 3) {
            VStack(alignment: .leading, spacing: 5) {
                if !message.text.isEmpty { Text(verbatim: message.text).textSelection(.enabled) }
                ForEach(message.attachments.indices, id: \.self) { i in
                    Label(message.attachments[i], systemImage: "paperclip")
                        .font(.callout).lineLimit(2)
                }
            }
            .font(.body)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(user ? Color(red: 0.05, green: 0.35, blue: 0.76) : .white.opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 15))
            Text(message.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: ([speaker, message.text] + message.attachments).filter { !$0.isEmpty }.joined(separator: ", ")))
        .accessibilityValue(Text(message.date, format: .dateTime))
        .frame(maxWidth: .infinity, alignment: user ? .trailing : .leading)
        .padding(user ? .leading : .trailing, 38)
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
