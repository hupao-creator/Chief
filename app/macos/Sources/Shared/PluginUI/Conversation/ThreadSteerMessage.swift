import QuartzCore
import SwiftUI

/// A retained follow-up is a reading entry, not proof of native admission or model processing.
public struct ThreadSteerMessage: View {
    public let content: String
    public let createdAt: Double?
    public let details: AnyView?
    @State private var expanded = false
    @Environment(\.locale) private var locale

    public init(content: String, createdAt: Double? = nil, details: AnyView? = nil) {
        self.content = content; self.createdAt = createdAt; self.details = details
    }

    public var body: some View {
        Group {
            if expanded || details != nil || content.contains(where: \.isNewline) {
                messageBody(canExpand: true)
            } else {
                // Fit the actual text, including narrow Sidecards and font fallback,
                // rather than guessing truncation from a character count.
                ViewThatFits(in: .horizontal) {
                    messageBody(canExpand: false)
                    messageBody(canExpand: true)
                }
            }
        }.padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(NativePalette.thread.ink.swiftUI)
            .background(NativePalette.thread.surface.swiftUI, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(localize("你的补充"))
    }

    private func messageBody(canExpand: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if expanded, let details { details }
            else {
                // Keep submitted text literal; collapsed rows must not load Markdown media.
                Text(content.isEmpty && details != nil ? localize("附件或批注") : content)
                    .font(NativeTypography.inter(size: 13))
                    .lineLimit(expanded ? nil : 1).textSelection(.enabled)
                    .fixedSize(horizontal: !canExpand, vertical: true)
            }
            HStack(spacing: 6) {
                if let createdAt {
                    Text(Date(timeIntervalSince1970: createdAt / 1_000), format: .dateTime.hour().minute().second())
                        .foregroundStyle(NativePalette.thread.muted.swiftUI)
                        .help(formatThreadTimestamp(createdAt))
                }
                Spacer(minLength: 4)
                if canExpand {
                    Button(localize(expanded ? "收起全文" : "展开全文")) {
                        withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                    }.buttonStyle(.plain).foregroundStyle(NativePalette.thread.accent.swiftUI)
                }
            }.font(NativeTypography.inter(size: 10)).frame(minHeight: 12)
        }
    }

    private func localize(_ text: String) -> String { NativePluginLocalization.localize(text, locale: locale) }
}

/// Capture, receipt and retained chronology can each remount the row. Drawing
/// from the original capture instant preserves one entrance across those updates.
struct ThreadSteerEntrance: ViewModifier {
    let capturedAt: TimeInterval?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settledCapture: TimeInterval?

    func body(content: Content) -> some View {
        if let capturedAt {
            let duration = NativeReadingPageTiming.duration
            let end = capturedAt + duration
            let settled = settledCapture == capturedAt || reduceMotion || CACurrentMediaTime() >= end
            TimelineView(.animation(paused: settled)) { _ in
                let elapsed = CACurrentMediaTime() - capturedAt
                let progress = settled ? 1 : NativeReadingPageTiming.replacementProgress(at: elapsed / duration)
                content
                    .opacity(progress)
                    .offset(y: NativeStreamingPageMetrics.entranceTravel * (1 - progress))
            }
            .onChange(of: reduceMotion, initial: true) { _, reduced in
                if reduced { settledCapture = capturedAt }
            }
            .task(id: capturedAt) {
                guard !settled else { return }
                let remaining = end - CACurrentMediaTime()
                if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
                if !Task.isCancelled { settledCapture = capturedAt }
            }
        } else {
            content
        }
    }
}
