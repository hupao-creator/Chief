import SwiftUI

package struct ThreadRequestHeader: View {
    let title: String
    let description: String?
    let question: Bool
    let monospaced: Bool
    package init(_ title: String, description: String? = nil, question: Bool, monospaced: Bool = false) {
        self.title = title
        self.description = description
        self.question = question
        self.monospaced = monospaced
    }

    package var body: some View {
        HStack(alignment: .top, spacing: 9) {
            NativeIcon(name: question ? "MessageSquare" : "ShieldCheck", size: 15)
                .foregroundStyle(NativePalette.thread.muted.swiftUI).padding(.top, 3)
            VStack(alignment: .leading, spacing: 9) {
                Text(title).font(NativeTypography.inter(size: 16, weight: 600))
                    .foregroundStyle(NativePalette.thread.inkStrong.swiftUI).textSelection(.enabled)
                if let description, !description.isEmpty {
                    Text(description).font(monospaced ? .system(size: 12, design: .monospaced) : NativeTypography.inter(size: 13))
                        .foregroundStyle(NativePalette.thread.muted.swiftUI).textSelection(.enabled)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.bottom, 17)
    }
}

package struct ThreadRequestButtonStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var enabled
    package init(primary: Bool = false) { self.primary = primary }
    package func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(NativeTypography.inter(size: 11, weight: 500))
            .foregroundStyle(primary ? NativePalette.thread.canvas.swiftUI : NativePalette.thread.muted.swiftUI)
            .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 34)
            .background(primary ? NativePalette.thread.accent.swiftUI : configuration.isPressed ? NativePalette.thread.surface.swiftUI : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
    }
}

package struct ThreadRequestActions: Layout {
    private let gap: CGFloat = 8
    package init() {}
    package func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        positions(proposal: proposal, subviews: subviews).size
    }
    package func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = positions(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        for (index, view) in subviews.enumerated() {
            let item = layout.items[index]
            view.place(at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y), proposal: ProposedViewSize(item.size))
        }
    }
    private func positions(proposal: ProposedViewSize, subviews: Subviews) -> (items: [CGRect], size: CGSize) {
        let width = proposal.width ?? .infinity
        var items: [CGRect] = []; var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0; var maxX: CGFloat = 0
        for view in subviews {
            let natural = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(width, natural.width), height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + gap; rowHeight = 0 }
            items.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            maxX = max(maxX, x + size.width); x += size.width + gap; rowHeight = max(rowHeight, size.height)
        }
        return (items, CGSize(width: proposal.width ?? maxX, height: y + rowHeight))
    }
}
