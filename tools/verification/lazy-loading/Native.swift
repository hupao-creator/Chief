import AppKit
import ChiefComposition
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import CryptoKit
import SwiftUI

@MainActor
private func measure<T>(_ action: () throws -> T) rethrows -> (T, Double) {
    let start = DispatchTime.now().uptimeNanoseconds
    let value = try action()
    return (value, Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
}

@main
struct NativeProbe {
    @MainActor static func main() throws {
        try prepareIsolatedNativeReplay()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        NativeTypography.registerFonts()
        let (plugins, registration) = try measure { try NativePlugins.make() }
        let (_, vector) = measure { plugins.harnesses.modules.map { $0.logo(size: 12) } }
        var assets: [[String: Any]] = []
        for plugin in plugins.harnesses.modules {
            let (source, first) = measure { plugin.logoSource }
            let (catalog, translation) = measure { plugin.translations }
            let (again, repeatMS) = measure { (plugin.logoSource, plugin.translations) }
            precondition(!source.isEmpty && again.0 == source && again.1 == catalog)
            assets.append(["id": plugin.descriptor.id.string, "firstSourceMS": first,
                "firstTranslationsMS": translation, "repeatBothMS": repeatMS,
                "sourceBytes": source.utf8.count, "sourceSHA256": SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined(),
                "entries": catalog.values.reduce(0) { $0 + $1.count }])
        }

        let count = 256
        var constructed: [String] = []
        func fallback(_ id: String) -> AnyView {
            constructed.append(id)
            return AnyView(Text(id))
        }
        let (rows, directoryMS) = measure {
            (0..<count).map { i in
                let id = "turn-\(i)"
                return ThreadConversationRow(id: JSONText(id), createdAt: Double(i),
                    execution: .init(id: JSONText(id), prompt: "Question \(i)", answer: "Answer \(i)"),
                    node: fallback(id))
            }
        }
        let directoryCalls = constructed.count
        // The scope renderer supplies the mounted body, as it does in each Harness.
        let registry = NativeReadingInteractions()
        let visit = UUID()
        let context = HarnessRenderContext(content: .manifest, presentation: .main(excludedExecutionIDs: []),
            contentResource: { _ in preconditionFailure("Fixture bodies are synchronous") }, onIndexChange: { _ in })
        let window = NSPanel(contentRect: .init(x: 10, y: 10, width: 920, height: 680),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        var bodyIDs = Set<String>()
        func root(target: ThreadConversationReadingTarget? = nil) -> some View {
            ThreadConversation(threadId: "probe", title: "Probe", rows: rows, readingTarget: target, context: context,
                renderRow: { key in
                    AnyView(Text(key.string).onAppear { bodyIDs.insert(key.string) })
                })
                .environment(\.threadAgentDetail, true)
                .environment(\.nativeReadingInteractions, registry)
                .environment(\.nativeReadingInteractionVisit, visit)
        }
        let start = DispatchTime.now().uptimeNanoseconds
        let host = NSHostingView(rootView: root())
        window.contentView = host
        window.orderBack(nil)
        func waitFor(_ id: String) throws {
            let deadline = Date().addingTimeInterval(15)
            repeat {
                host.layoutSubtreeIfNeeded()
                if bodyIDs.contains(id), registry.snapshot(visit: visit).contains(where: {
                    $0["role"] == .text("conversation") && $0["value"]?["selectedRow"] == .text(id)
                        && $0["value"]?["transitioning"] == .bool(false)
                }) { return }
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            } while Date() < deadline
            throw NSError(domain: "Missing mounted row " + id, code: 1)
        }
        try waitFor("turn-255")
        let openMS = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        let (_, historyMS) = try measure {
            host.rootView = root(target: .init(requestId: "history", mode: .history, executionId: "turn-0"))
            try waitFor("turn-0")
        }
        let scopedCalls = constructed.count - directoryCalls
        window.orderOut(nil)
        window.contentView = nil
        let (_, firstInline) = measure { rows[0].node }
        let (_, repeatInline) = measure { rows[0].node }
        precondition(bodyIDs == ["turn-255", "turn-0"])
        let report: [String: Any] = ["registrationMS": registration, "nativeLogosMS": vector, "assets": assets,
            "directoryMS": directoryMS, "rows": count, "directoryFallbackCalls": directoryCalls,
            "scopedFallbackCalls": scopedCalls, "mounted": bodyIDs.sorted(), "openMS": openMS, "historyMS": historyMS,
            "firstInlineMS": firstInline, "repeatInlineMS": repeatInline,
            "inlineFallbackCalls": constructed.count - directoryCalls - scopedCalls]
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
