import ChiefPluginAPI
import SwiftUI

/// Fits the existing dispatch capsule without borrowing its eyes or Stop seat.
struct NativeMokuDispatchContent: View {
    let dispatch: NativeMokuDispatch
    let harness: AnyHarnessPlugin?
    @Environment(\.locale) private var locale
    private var chinese: Bool { locale.language.languageCode?.identifier == "zh" }

    private struct Label: Hashable {
        let status: String
        let model, thinking: String?
    }

    var body: some View {
        let label = Label(status: dispatch.sentence(chinese: chinese), model: dispatch.model, thinking: dispatch.thinking)
        HStack(spacing: 8) {
            ZStack {
                Group {
                    if let harness { harness.logo(size: 15).help(harness.descriptor.displayName.string) }
                    else { Image(systemName: "arrow.up.forward.app").frame(width: 15).help(dispatch.harnessID.string) }
                }
                .id(dispatch.harnessID)
                .transition(.opacity)
            }.mokuInk(value: dispatch.harnessID)
            // The status width determines the configuration's position and can
            // switch the fit from one line to two. Exchange the whole text row
            // through clear so no surviving word jumps between the two layouts.
            ZStack(alignment: .leading) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        status(label.status)
                        if !dispatch.configuration.isEmpty { configuration }
                    }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 2) {
                        status(label.status)
                        if !dispatch.configuration.isEmpty { configuration }
                    }
                }
                .id(label)
                .transition(.modifier(active: NativeMokuHandoffInk(progress: 0), identity: NativeMokuHandoffInk(progress: 1)))
            }
            .mokuInk(value: label)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .lineLimit(1).truncationMode(.tail)
        .frame(maxWidth: .infinity, minHeight: 32)
        .accessibilityElement(children: .contain)
    }

    private func status(_ sentence: String) -> some View {
        Text(sentence)
            .font(.system(size: 13, weight: .medium))
            .accessibilityIdentifier("moku-dispatch-status")
    }

    private var configuration: some View {
        // Try the complete identifiers first. Narrow seats lend configuration a
        // second line before truncating the model; never invent a model alias.
        HStack(spacing: 5) {
            if let model = dispatch.model { Text(model).truncationMode(.middle) }
            if let thinking = dispatch.thinking {
                if dispatch.model != nil { Text("·").accessibilityHidden(true) }
                Text(thinking).layoutPriority(1)
            }
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
        .help(dispatch.configuration)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dispatch.configuration)
        .accessibilityIdentifier("moku-dispatch-configuration")
    }
}
