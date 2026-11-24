import ChiefCore
import SwiftUI

struct NativeMokuConversationTimeline: View {
    let page: NativeMokuConversationPage
    let showEarlier: (JSONText) -> Void
    let showNewer: (() -> Void)?
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var viewport
    @State private var position = ScrollPosition()
    @State private var atBottom = true
    @State private var revealed: CGFloat = 0

    private struct ReadingViewport: Equatable {
        let height: CGFloat
        let nearEnd: Bool
    }

    private let timeColumn: CGFloat = 78
    private var chinese: Bool { locale.language.languageCode?.identifier == "zh" }

    var body: some View {
        GeometryReader { bounds in
            let width = bounds.size.width
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    // Measure the bounded conversation page at its rendered width before sizing the Dock.
                    VStack(alignment: .leading, spacing: 0) {
                        if let cursor = page.before {
                            pageButton(chinese ? "较早消息" : "Earlier messages", width: width) { showEarlier(cursor) }
                                .accessibilityIdentifier("moku-conversation-earlier")
                        }
                        ForEach(page.messages.enumerated(), id: \.element.id) { index, message in
                            let previous = index > 0 ? page.messages[index - 1] : nil
                            let starts = previous.map { startsPeriod(message, after: $0) } ?? true
                            let bubbleSpacing: CGFloat = previous?.fromUser == message.fromUser ? 7 : 14
                            let next = index + 1
                            let tail = next == page.messages.count || page.messages[next].fromUser != message.fromUser
                                || startsPeriod(page.messages[next], after: message)
                            VStack(alignment: .leading, spacing: 0) {
                                if starts {
                                    separator(message.date)
                                        .frame(width: width).offset(x: revealed)
                                        .padding(.top, index == 0 ? 2 : 20).padding(.bottom, 8)
                                }
                                HStack(spacing: 0) {
                                    ConversationBubble(message: message, tail: tail, viewport: viewport,
                                                       viewportHeight: bounds.size.height, chinese: chinese)
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
                        if let showNewer {
                            pageButton(chinese ? "较新消息" : "Newer messages", width: width, action: showNewer)
                                .accessibilityIdentifier("moku-conversation-newer")
                        }
                    }
                    .frame(width: width + timeColumn, alignment: .leading)
                    .padding(.vertical, 12)
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
                    ReadingViewport(height: geometry.containerSize.height,
                                    nearEnd: geometry.contentSize.height - geometry.visibleRect.maxY < 24)
                } action: { before, after in
                    atBottom = after.nearEnd
                    // A taller draft can shrink the viewport while the last message ID stays the same.
                    if before.nearEnd, after.height < before.height, revealed < 1 { position.scrollTo(edge: .bottom) }
                }
                .onScrollPhaseChange { _, phase, context in
                    if (phase == .idle || phase == .decelerating), context.geometry.visibleRect.minX > 0.5 {
                        // A point preserves the reader's vertical offset on a two-axis scroll view.
                        let resting = CGPoint(x: 0, y: context.geometry.visibleRect.minY)
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { position.scrollTo(point: resting) }
                    }
                }
                .onChange(of: page.messages.last?.id) { _, last in
                    if atBottom, revealed < 1, let last { proxy.scrollTo(last, anchor: .bottomLeading) }
                }
            }
        }
        .coordinateSpace(name: viewport)
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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let user = message.fromUser
        let shape = ConversationBalloon(outgoing: user, tail: tail)
        let speaker = user ? (chinese ? "你" : "You") : "Chief"
        let spoken = ([speaker, message.text] + message.attachments).filter { !$0.isEmpty }.joined(separator: ", ")
        VStack(alignment: .leading, spacing: 4) {
            if !message.text.isEmpty { Text(verbatim: message.text).textSelection(.enabled) }
            ForEach(message.attachments.indices, id: \.self) { i in
                Label(message.attachments[i], systemImage: "paperclip").font(.callout).lineLimit(2)
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(user || scheme == .dark ? Color.white : .black)
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
                shape.fill(scheme == .dark ? Color(red: 0.19, green: 0.19, blue: 0.20)
                                          : Color(red: 0.914, green: 0.914, blue: 0.918))
            }
        }
        .help(Text(message.date, format: .dateTime))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
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
