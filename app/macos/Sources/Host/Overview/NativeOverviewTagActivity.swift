import ChiefPluginUI
import SwiftUI

extension EnvironmentValues {
    @Entry var overviewTagActivityVisible = true
}

struct OverviewTagActivityIndicator: View {
    enum Space { case workspace }
    let diameter: CGFloat
    @State private var inViewport = false
    @Environment(\.overviewTagActivityVisible) private var visible

    var body: some View {
        Color.clear
            .frame(width: diameter, height: diameter)
            .onGeometryChange(for: Bool.self) { geometry in
                let disk = CGRect(origin: .zero, size: geometry.size)
                let workspace = geometry.bounds(of: .named(Space.workspace)) ?? disk
                let scroll = geometry.bounds(of: .scrollView(axis: .horizontal)) ?? disk
                return !disk.intersection(workspace).intersection(scroll).isEmpty
            } action: { inViewport = $0 }
            .overlay {
                if visible && inViewport { NativeTagActivityPerforations() }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
