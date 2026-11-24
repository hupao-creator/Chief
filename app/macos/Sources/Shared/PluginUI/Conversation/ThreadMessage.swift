import SwiftUI
import ChiefCore
import UniformTypeIdentifiers

public struct ThreadMessageAttachment: Identifiable, Hashable, Sendable {
    public let id: JSONText
    public let label: String
    public let title: String?
    private let mimeType: String?
    private let kind: String?
    public init(id: JSONText, label: String, title: String? = nil, mimeType: String? = nil, kind: String? = nil) {
        self.id = id; self.label = label; self.title = title
        self.mimeType = mimeType; self.kind = kind
    }

    var mayPreviewImage: Bool {
        // Remote and native-only attachment references have synthetic IDs.
        guard UUID(uuidString: id.string) != nil else { return false }
        if kind == "image" { return true }
        if let mime = mimeType?.lowercased(), !mime.isEmpty, mime != "application/octet-stream" {
            return mime.hasPrefix("image/")
        }
        let ext = (label as NSString).pathExtension
        return UTType(filenameExtension: ext)?.conforms(to: .image) == true
    }
}

/// Annotation presentation only: browser selection metadata remains with its owner.
public struct ThreadMessageAnnotation: Identifiable, Hashable, Sendable {
    public let id: JSONText
    public let url: String
    public let title: String?
    public let comment: String
    public let screenshotId: JSONText?
    public init(id: JSONText, url: String, title: String? = nil, comment: String, screenshotId: JSONText? = nil) {
        self.id = id; self.url = url; self.title = title; self.comment = comment; self.screenshotId = screenshotId
    }
}

/// User and assistant messages render through the native Markdown document.
public struct ThreadMessage: View {
    public enum Author: String, Sendable { case user, assistant }
    public let id: JSONText
    public let author: Author
    public let content: String
    // Preserve byte-distinct input at the outer SwiftUI comparison boundary too.
    private let contentBytes: Data
    public let streaming: Bool
    public let steeringLabel: String?
    public let annotations: [ThreadMessageAnnotation]
    public let attachments: [ThreadMessageAttachment]
    public let actions: AnyView?
    public let openExternal: ((URL) -> Void)?
    public let resolveMedia: NativeMarkdownMediaResolver?
    public let previewAttachment: ((JSONText) async throws -> Data)?
    private let resolveAttachmentImage: ((JSONText) async throws -> URL)?
    @Environment(\.locale) private var locale
    @State private var annotationsExpanded = false
    @State private var attachmentPreviewURL: URL?

    public init(id: JSONText, author: Author, content: String, streaming: Bool = false,
                steeringLabel: String? = nil, annotations: [ThreadMessageAnnotation] = [],
                attachments: [ThreadMessageAttachment] = [], actions: AnyView? = nil,
                openExternal: ((URL) -> Void)? = nil,
                resolveMedia: NativeMarkdownMediaResolver? = nil,
                previewAttachment: ((JSONText) async throws -> Data)? = nil,
                resolveAttachmentImage: ((JSONText) async throws -> URL)? = nil) {
        self.id = id; self.author = author; self.content = content; self.streaming = streaming
        self.contentBytes = Data(content.utf8)
        self.steeringLabel = steeringLabel; self.annotations = annotations; self.attachments = attachments
        self.actions = actions; self.openExternal = openExternal; self.resolveMedia = resolveMedia; self.previewAttachment = previewAttachment
        self.resolveAttachmentImage = resolveAttachmentImage
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if author == .user, let steeringLabel {
                Text(steeringLabel).font(NativeTypography.inter(size: 10, weight: 500))
                    .foregroundStyle(NativeAppKitPalette.thread.muted.swiftUI)
            }
            NativeMarkdownView(text: content, streaming: streaming, openExternal: openExternal, resolveMedia: resolveMedia)
            actions
            if author == .user {
                if !attachments.isEmpty {
                    ThreadAttachmentFlow {
                        ForEach(attachments) { attachment in
                            ThreadAttachmentTile(attachment: attachment, resolve: resolveAttachmentImage) {
                                attachmentPreviewURL = $0
                            }
                        }
                    }
                    .quickLookPreview($attachmentPreviewURL)
                }
                if !annotations.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Button { annotationsExpanded.toggle() } label: {
                            HStack(spacing: 5) {
                                NativeIcon(name: "ChevronRight", size: 12).rotationEffect(.degrees(annotationsExpanded ? 90 : 0))
                                Text("\(NativePluginLocalization.localize("网页批注", locale: locale)) · \(annotations.count)")
                            }.font(NativeTypography.inter(size: 11))
                        }.buttonStyle(.plain)
                        if annotationsExpanded {
                            ForEach(annotations) { annotation in
                                ThreadAnnotationPreview(annotation: annotation, openExternal: openExternal, preview: previewAttachment)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, author == .user ? 14 : 0)
        .padding(.horizontal, author == .user ? 16 : 0)
        .background(author == .user ? NativeAppKitPalette.thread.surface.swiftUI : .clear, in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct ThreadAttachmentTile: View {
    let attachment: ThreadMessageAttachment
    let resolve: ((JSONText) async throws -> URL)?
    let preview: (URL) -> Void
    @State private var thumbnail: (attachment: ThreadMessageAttachment, image: CGImage, url: URL)?

    var body: some View {
        Group {
            if let thumbnail, thumbnail.attachment == attachment {
                let image = thumbnail.image
                let width = CGFloat(image.width)
                let height = CGFloat(image.height)
                let scale = min(360 / width, 220 / height, 1)
                Button { preview(thumbnail.url) } label: {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(width / height, contentMode: .fit)
                        .frame(idealWidth: width * scale, maxWidth: width * scale)
                        .clipShape(.rect(cornerRadius: 5))
                }.buttonStyle(.plain)
                    .accessibilityLabel(attachment.label)
            } else {
                HStack(spacing: 5) {
                    NativeIcon(name: "Paperclip", size: 12)
                    Text(attachment.label).lineLimit(1)
                }.font(NativeTypography.inter(size: 11))
                    .foregroundStyle(NativeAppKitPalette.thread.muted.swiftUI)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(NativeAppKitPalette.thread.canvas.swiftUI, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(NativeAppKitPalette.thread.line.swiftUI))
            }
        }
        .help(attachment.title ?? attachment.label)
        .task(id: attachment) {
            thumbnail = nil
            guard attachment.mayPreviewImage, let resolve,
                  let url = try? await resolve(attachment.id), !Task.isCancelled,
                  let image = await NativeComposerThumbnailLoader.load(path: url.path, maxPixelSize: 720),
                  !Task.isCancelled else { return }
            thumbnail = (attachment, image, url)
        }
    }
}

private struct ThreadAnnotationPreview: View {
    @Environment(\.openURL) private var defaultOpenURL
    let annotation: ThreadMessageAnnotation
    let openExternal: ((URL) -> Void)?
    let preview: ((JSONText) async throws -> Data)?
    @Environment(\.locale) private var locale
    @State private var image: NativePlatformImage?
    @State private var expanded = false
    @State private var loading = false
    @State private var failure: String?
    @State private var previewTask: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(annotation.comment).textSelection(.enabled)
            if let url = URL(string: annotation.url) {
                Button(annotation.title?.isEmpty == false ? annotation.title! : annotation.url) {
                    if let openExternal { openExternal(url) } else { defaultOpenURL(url) }
                }.buttonStyle(.plain).foregroundStyle(NativeAppKitPalette.thread.accent.swiftUI)
                    .accessibilityAddTraits(.isLink)
            }
            if annotation.screenshotId != nil {
                Button(localize(loading ? "加载截图…" : expanded ? "收起截图" : "预览截图"), action: togglePreview)
                    .buttonStyle(.plain).disabled(loading || preview == nil)
            } else { Text(localize("仅文字批注")).foregroundStyle(NativeAppKitPalette.thread.muted.swiftUI) }
            if let failure { Text(failure).foregroundStyle(NativeAppKitPalette.thread.danger.swiftUI).textSelection(.enabled) }
            if expanded, let image { image.swiftUI.resizable().scaledToFit().accessibilityLabel(annotation.comment) }
        }.font(NativeTypography.inter(size: 12)).padding(.vertical, 8)
            .onDisappear { previewTask?.cancel(); previewTask = nil; loading = false }
    }
    private func localize(_ value: String) -> String { NativePluginLocalization.localize(value, locale: locale) }
    private func togglePreview() {
        if expanded { expanded = false; return }
        if image != nil { expanded = true; return }
        guard !loading, let screenshotId = annotation.screenshotId, let preview else { return }
        loading = true; failure = nil
        previewTask = Task { @MainActor in
            defer { loading = false; previewTask = nil }
            do {
                let data = try await preview(screenshotId)
                try Task.checkCancellation()
                guard let decoded = NativePlatformImage(data: data) else { throw AnnotationImageError() }
                image = decoded; expanded = true
            } catch is CancellationError { }
            catch { failure = error.localizedDescription }
        }
    }
}
private struct AnnotationImageError: LocalizedError {
    var errorDescription: String? { "The annotation screenshot is not a supported image." }
}

/// Small attachment chips wrap without imposing a grid or truncating their container.
private struct ThreadAttachmentFlow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        positions(width: proposal.width ?? 744, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = positions(width: bounds.width, subviews: subviews)
        for (index, item) in subviews.enumerated() {
            let rect = layout.frames[index]
            item.place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY), proposal: ProposedViewSize(rect.size))
        }
    }
    private func positions(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var frames: [CGRect] = []
        for item in subviews {
            var size = item.sizeThatFits(.unspecified)
            if size.width > width {
                size = item.sizeThatFits(.init(width: width, height: nil))
                size.width = min(size.width, width)
            }
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + 6; rowHeight = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + 6; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), frames)
    }
}

package extension ThreadMessageAnnotation {
    init(json: JSONValue) {
        let id: JSONText
        if case .string(let value) = json["id"] { id = value } else { id = "" }
        let screenshot: JSONText?
        if case .string(let value) = json["screenshotId"] { screenshot = value } else { screenshot = nil }
        self.init(id: id, url: json["url"]?.stringValue ?? "", title: json["title"]?.stringValue,
                  comment: json["comment"]?.stringValue ?? "", screenshotId: screenshot)
    }
}
