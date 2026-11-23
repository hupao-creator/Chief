import ChiefCore
import ChiefPluginAPI
import SwiftUI

struct ThreadTranscriptBody: View {
    let item: ThreadTranscriptItem
    let active: Bool
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    @Environment(\.threadAgentDetail) private var agentDetail
    @Environment(\.locale) private var locale

    var body: some View {
        switch item.body {
        case let .user(input):
            let message = ThreadMessage(id: item.id, author: .user, content: input.text,
                steeringLabel: agentDetail ? nil : localized(input.followUp ? "补充" : "你"),
                annotations: input.annotations, attachments: input.attachments,
                openExternal: openExternal, resolveMedia: context.resolveMedia, previewAttachment: context.previewAttachment)
            if agentDetail {
                ThreadSteerMessage(content: input.text, createdAt: input.createdAt,
                    details: input.annotations.isEmpty && input.attachments.isEmpty ? nil : AnyView(message))
                    .modifier(ThreadSteerEntrance(capturedAt: input.localCaptureTime))
            } else { message }
        case let .reply(text, _, _):
            ThreadMessage(id: item.id, author: .assistant, content: text, openExternal: openExternal, resolveMedia: context.resolveMedia)
        case let .reasoning(text, _):
            ThreadSurfaceDisclosure(label: localized("思考过程")) {
                NativeMarkdownView(text: text, streaming: active, muted: true,
                                   openExternal: openExternal, resolveMedia: context.resolveMedia)
            }
        case let .review(text):
            ThreadTranscriptReview {
                NativeMarkdownView(text: text, openExternal: openExternal, resolveMedia: context.resolveMedia)
            }
        case let .resolution(title, status):
            HStack(spacing: 5) {
                NativeIcon(name: "Check", size: 13)
                Text(title + " · " + localized(status))
            }.font(NativeTypography.inter(size: 11)).foregroundStyle(NativePalette.thread.muted.swiftUI)
                .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        case let .notice(text): ThreadTranscriptNotice(text)
        case .compaction: ThreadTranscriptNotice(localized("上下文已压缩"))
        case let .error(text): ThreadTranscriptFailure(message: text.isEmpty ? localized("回复失败") : text)
        case .request, .activity: EmptyView()
        }
    }

    private func localized(_ text: String) -> String { NativePluginLocalization.localize(text, locale: locale) }
    private func openExternal(_ url: URL) { Task { try? await actions.openExternal(JSONText(url.absoluteString)) } }
}

package struct ThreadTranscriptNotice: View {
    let text: String
    package init(_ text: String) { self.text = text }
    package var body: some View {
        Text(text).font(NativeTypography.inter(size: 11)).foregroundStyle(NativePalette.thread.muted.swiftUI)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).textSelection(.enabled)
    }
}

package struct ThreadTranscriptFailure: View {
    let message: String
    var detail: String?
    var retry: (() async throws -> Void)?
    @Environment(\.locale) private var locale
    @State private var retryError: String?
    package init(message: String, detail: String? = nil, retry: (() async throws -> Void)? = nil) {
        self.message = message
        self.detail = detail
        self.retry = retry
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                NativeIcon(name: "CircleAlert", size: 13)
                Text(retryError ?? message).textSelection(.enabled)
            }
            if let detail { Text(detail).font(NativeTypography.mono(size: 10)).textSelection(.enabled) }
            if let retry {
                Button(NativePluginLocalization.localize("重试", locale: locale)) {
                    Task { do { try await retry(); retryError = nil } catch { retryError = error.localizedDescription } }
                }.buttonStyle(.plain)
            }
        }.font(NativeTypography.inter(size: 12)).foregroundStyle(NativePalette.thread.danger.swiftUI)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(NativePalette.thread.lineSoft.swiftUI).frame(height: 1) }
            .padding(.vertical, 12)
            .accessibilityElement(children: .contain)
            .nativeThreadDocumentMargins()
            .nativeReadingContentReady()
    }
}

private struct ThreadTranscriptReview<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var expanded = false
    @State private var hovered = false
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 7) {
                    NativeIcon(name: "GitPullRequest", size: 13)
                    Text("Review").font(NativeTypography.inter(size: 11, weight: 620)).foregroundStyle(NativePalette.thread.ink.swiftUI)
                    Spacer(minLength: 0)
                    NativeIcon(name: expanded ? "ChevronDown" : "ChevronRight", size: 13)
                }.font(NativeTypography.inter(size: 11))
                    .foregroundStyle((hovered ? NativePalette.thread.ink : NativePalette.thread.muted).swiftUI)
                    .padding(.vertical, 4).contentShape(Rectangle())
            }.buttonStyle(.plain).onHover { hovered = $0 }
                .accessibilityValue(NativePluginLocalization.localize(expanded ? "已展开" : "已收起", locale: locale))
            if expanded { content().padding(.top, 10) }
        }
    }
}
