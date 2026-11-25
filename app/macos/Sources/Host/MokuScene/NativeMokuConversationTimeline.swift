import ChiefCore
import SwiftUI

struct NativeMokuConversationTimeline: View {
    let page: NativeMokuConversationPage
    var workspace: NativeWorkspaceModel?
    let showEarlier: (JSONText) -> Void
    let showNewer: (() -> Void)?
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var viewport
    // Target the inset below the last bubble when the timeline first mounts.
    @State private var position = ScrollPosition(id: TimelineEnd.bottom, anchor: .bottomLeading)
    @State private var atBottom = true
    @State private var scrolling = false
    @State private var revealed: CGFloat = 0

    private struct ReadingViewport: Equatable {
        let height: CGFloat
        let documentHeight: CGFloat
        let nearEnd: Bool
        let atEnd: Bool
    }
    private enum TimelineEnd: Hashable { case bottom }

    private let timeColumn: CGFloat = 78
    private var chinese: Bool { locale.language.languageCode?.identifier == "zh" }

    var body: some View {
        GeometryReader { bounds in
            let width = bounds.size.width
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let cursor = page.before {
                            pageButton(chinese ? "较早消息" : "Earlier messages", width: width) { showEarlier(cursor) }
                                .accessibilityIdentifier("moku-conversation-earlier")
                        }
                        // The trailing rows and the end target share one exact layout. A tall last
                        // reply must not resolve to a lazy height estimate on entry or on send.
                        let rows = page.messages.enumerated()
                        let tailCount = 6
                        if rows.count > tailCount {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(rows.dropLast(tailCount), id: \.element.id) { index, message in
                                    row(message, at: index, width: width, height: bounds.size.height)
                                }
                            }
                        }
                        ForEach(rows.suffix(tailCount), id: \.element.id) { index, message in
                            row(message, at: index, width: width, height: bounds.size.height)
                        }
                        if let showNewer {
                            pageButton(chinese ? "较新消息" : "Newer messages", width: width, action: showNewer)
                                .accessibilityIdentifier("moku-conversation-newer")
                        }
                        Color.clear.frame(height: 12).id(TimelineEnd.bottom)
                    }
                    .scrollTargetLayout()
                    .frame(width: width + timeColumn, alignment: .leading)
                    .padding(.top, 12)
                    .reportMokuConversationHeight()
                }
                .scrollIndicators(.hidden, axes: .horizontal)
                .defaultScrollAnchor(.bottomLeading, for: .initialOffset)
                .defaultScrollAnchor(atBottom ? .bottomLeading : nil, for: .sizeChanges)
                .defaultScrollAnchor(.topLeading, for: .alignment)
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGFloat.self) { min(timeColumn, max(0, $0.visibleRect.minX)) } action: { _, x in
                    revealed = x
                }
                .onScrollGeometryChange(for: ReadingViewport.self) { geometry in
                    let gap = geometry.contentSize.height - geometry.visibleRect.maxY
                    return ReadingViewport(height: geometry.containerSize.height, documentHeight: geometry.contentSize.height,
                                           nearEnd: gap < 24, atEnd: gap <= 1)
                } action: { before, after in
                    let resized = before.height != after.height || before.documentHeight != after.documentHeight
                    // Layout can change the gap before the native offset settles. Only a reader
                    // moving through the document gives up following the latest reply.
                    if !scrolling, revealed < 1, before.nearEnd, after.height < before.height {
                        // A point used to release horizontal timestamps otherwise survives a
                        // window or editor resize, even when the last bubble stayed visible.
                        position.scrollTo(edge: .bottom)
                    } else if scrolling || (!resized && position.isPositionedByUser) {
                        atBottom = after.nearEnd
                    } else if resized, atBottom, !after.atEnd, revealed < 1 {
                        position.scrollTo(edge: .bottom)
                    }
                }
                .onScrollPhaseChange { _, phase, context in
                    scrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                    if (phase == .idle || phase == .decelerating), context.geometry.visibleRect.minX > 0.5 {
                        // A point preserves the reader's vertical offset on a two-axis scroll view.
                        let resting = CGPoint(x: 0, y: context.geometry.visibleRect.minY)
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { position.scrollTo(point: resting) }
                    }
                }
                .onChange(of: page.messages.last?.id) { _, last in
                    if atBottom, revealed < 1, last != nil { proxy.scrollTo(TimelineEnd.bottom, anchor: .bottomLeading) }
                }
            }
        }
        .coordinateSpace(name: viewport)
    }

    private func row(_ message: NativeMokuConversationPage.Message, at index: Int, width: CGFloat, height: CGFloat) -> some View {
        let previous = index > 0 ? page.messages[index - 1] : nil
        let starts = previous.map { startsPeriod(message, after: $0) } ?? true
        let bubbleSpacing: CGFloat = previous?.fromUser == message.fromUser ? 7 : 14
        let next = index + 1
        let tail = next == page.messages.count || page.messages[next].fromUser != message.fromUser
            || startsPeriod(page.messages[next], after: message)
        return VStack(alignment: .leading, spacing: 0) {
            if starts {
                separator(message.date)
                    .frame(width: width).offset(x: revealed)
                    .padding(.top, index == 0 ? 2 : 20).padding(.bottom, 8)
            }
            HStack(spacing: 0) {
                ConversationBubble(message: message, tail: tail, viewport: viewport,
                                   viewportHeight: height, chinese: chinese, workspace: workspace)
                    .frame(maxWidth: max(1, (width - 28) * 0.76),
                           alignment: message.fromUser ? .trailing : .leading)
                    .padding(.horizontal, 14)
                    .frame(width: width, alignment: message.fromUser ? .trailing : .leading)
                    .offset(x: message.fromUser ? 0 : revealed)
                Text(message.date, format: .dateTime.hour().minute())
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                    .lineLimit(1).padding(.trailing, 13)
                    .frame(width: timeColumn, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, starts ? 0 : bubbleSpacing)
        .id(message.id)
    }

    private func startsPeriod(_ message: NativeMokuConversationPage.Message, after previous: NativeMokuConversationPage.Message) -> Bool {
        !calendar.isDate(message.date, inSameDayAs: previous.date) || message.date.timeIntervalSince(previous.date) >= 15 * 60
    }

    private func pageButton(_ title: String, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            .padding(.vertical, 6).frame(width: width).offset(x: revealed)
    }

    private func separator(_ date: Date) -> some View {
        TimelineView(.everyMinute) { clock in
            let day = dayLabel(for: date, relativeTo: clock.date)
            Text("\(day.fontWeight(.semibold)) \(Text(date, format: .dateTime.hour().minute()))")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .accessibilityIdentifier("moku-conversation-period")
        }
    }

    private func dayLabel(for date: Date, relativeTo now: Date) -> Text {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day
        return switch days ?? Int.max {
        case 0: Text(verbatim: chinese ? "今天" : "Today")
        case 1: Text(verbatim: chinese ? "昨天" : "Yesterday")
        case 2...6: Text(date, format: .dateTime.weekday(.wide))
        default: Text(date, format: .dateTime.year().month(.abbreviated).day())
        }
    }
}

private struct ConversationBubble: View {
    let message: NativeMokuConversationPage.Message
    let tail: Bool
    let viewport: Namespace.ID
    let viewportHeight: CGFloat
    let chinese: Bool
    let workspace: NativeWorkspaceModel?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let user = message.fromUser
        let shape = ConversationBalloon(outgoing: user, tail: tail)
        let speaker = user ? (chinese ? "你" : "You") : "Chief"
        let talk = user ? nil : NativeMokuTalkText(message.text)
        let spoken = ([speaker, talk?.hasLinks == true ? "" : message.text] + message.attachments).filter { !$0.isEmpty }.joined(separator: ", ")
        VStack(alignment: .leading, spacing: 4) {
            if !message.text.isEmpty {
                if let talk, talk.hasLinks { NativeMokuTalkLinks(content: talk, workspace: workspace, compact: false) }
                else { Text(verbatim: message.text).textSelection(.enabled) }
            }
            ForEach(message.attachments.indices, id: \.self) { i in
                Label(message.attachments[i], systemImage: "paperclip").font(.callout).lineLimit(2)
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 13).padding(.vertical, 7)
        .padding(.bottom, tail ? ConversationBalloon.tailHeight : 0)
        .background {
            if user {
                // All outgoing balloons sample the same top-to-bottom wash in the viewport.
                GeometryReader { geo in
                    let y = geo.frame(in: .named(viewport)).minY
                    let height = max(1, geo.size.height)
                    let colors = contrast == .increased
                        ? [Color(red: 0.04, green: 0.39, blue: 0.79), Color(red: 0, green: 0.27, blue: 0.67)]
                        : [Color(red: 0.33, green: 0.74, blue: 0.99), Color(red: 0.02, green: 0.50, blue: 1)]
                    shape.fill(LinearGradient(colors: colors, startPoint: .init(x: 0.5, y: -y / height),
                                              endPoint: .init(x: 0.5, y: (viewportHeight - y) / height)))
                }
            } else {
                shape.fill(Color(red: 0.19, green: 0.19, blue: 0.20))
            }
        }
        .help(Text(message.date, format: .dateTime))
        .accessibilityElement(children: talk?.hasLinks == true ? .contain : .ignore)
        .accessibilityAddTraits(talk?.hasLinks == true ? [] : .isStaticText)
        .accessibilityLabel(Text("\(Text(verbatim: spoken)) — \(Text(message.date, format: .dateTime))"))
        .accessibilityIdentifier("moku-conversation-message")
    }
}

/// The terminal tail turns down from inside the lower corner and stays within the balloon's width.
private struct ConversationBalloon: Shape {
    static let tailHeight: CGFloat = 5.5
    let outgoing: Bool
    let tail: Bool

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height - (tail ? Self.tailHeight : 0)
        let r = min(19, w / 2, h / 2)
        guard tail else { return RoundedRectangle(cornerRadius: r, style: .continuous).path(in: rect) }
        var p = Path()
        p.move(to: .init(x: r, y: 0))
        p.addArc(tangent1End: .init(x: w, y: 0), tangent2End: .init(x: w, y: r), radius: r)
        p.addLine(to: .init(x: w, y: h - r))
        p.addCurve(to: .init(x: w - 5.6, y: h - 4.8), control1: .init(x: w, y: h - r * 0.56),
                   control2: .init(x: w - 2.3, y: h - 7.7))
        p.addCurve(to: .init(x: w - 7.1, y: h + Self.tailHeight), control1: .init(x: w - 10.5, y: h - 0.7),
                   control2: .init(x: w - 9.8, y: h + 2.2))
        p.addCurve(to: .init(x: w - r - 1, y: h), control1: .init(x: w - 12.8, y: h + 4.7),
                   control2: .init(x: w - 15.9, y: h))
        p.addArc(tangent1End: .init(x: 0, y: h), tangent2End: .init(x: 0, y: h - r), radius: r)
        p.addArc(tangent1End: .zero, tangent2End: .init(x: r, y: 0), radius: r)
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: outgoing ? rect.minX : rect.maxX, y: rect.minY)
            .scaledBy(x: outgoing ? 1 : -1, y: 1))
    }
}
