import ChiefCore
import ChiefPluginAPI
import ChiefUI
import SwiftUI

@MainActor
struct DemoReport {
    let plugin: AnyApplicationThreadPlugin
    let snapshot: ApplicationOverviewSnapshot
    let source: DemoThread
    let harness: AnyHarnessPlugin
    let story: DemoReportStory
    private let scope: ApplicationCapabilityScope

    init(_ story: DemoReportStory, plugin: AnyApplicationThreadPlugin, source: DemoThread, harness: AnyHarnessPlugin) throws {
        self.story = story
        self.plugin = plugin
        self.source = source
        self.harness = harness
        let ref = ApplicationThreadRef(threadID: JSONText(story.id), typeID: plugin.id)
        scope = .init(pluginID: plugin.ownerPluginID, thread: ref)
        let folder = source.thread.directoryTag
        let entry = ApplicationThreadCatalogEntry<JSONValue>(ref: ref, revision: 1, createdAt: source.thread.updatedAt,
            updatedAt: source.thread.updatedAt, title: JSONText(story.title), archived: false,
            tags: .init(tags: [folder] + source.thread.tags, semanticTags: source.thread.tags, directoryTags: [folder], tagEmojis: source.thread.tagEmojis), presentations: [],
            view: .object(["emoji": .text(story.emoji), "shortDescription": .text(story.intro), "previewText": .text(story.intro),
                "coverRevision": .text("cover-1"), "contentRevision": .text("brief-1"), "readingSeconds": .integer(25),
                "relatedExecutions": .array([Self.referenceJSON(source.reference)])]), scope: source.thread.directoryScope)
        snapshot = try plugin.projectCard(entry: entry, availableColumns: HarnessOverviewCapacity.maximumColumns,
            capabilities: .init(scope: scope, requires: plugin.requires, registrations: []))
    }

    private static func referenceJSON(_ ref: ApplicationExecutionRef) -> JSONValue {
        .object(["thread": ref.thread.json, "executionId": .string(ref.executionID)])
    }

    func context(theme: PluginTheme, locale: JSONText) throws -> ApplicationRendererContext {
        let entry = snapshot.entry
        let ref = source.reference
        let references = ApplicationExecutionReferencesUI(read: { requested in
            guard requested.contains(ref) else { return [] }
            return [try .init(reference: ref, title: source.thread.title, emoji: story.emoji, missing: false, running: false,
                harness: .init(id: harness.descriptor.id, displayName: harness.descriptor.displayName),
                preview: harness.executionPreview(thread: source.thread, executionID: ref.executionID))]
        }, subscribe: { _, _ in {} }, logo: { _, size in harness.logo(size: size) }, execution: { requested in
            guard requested == ref else { throw PluginContractError("Unknown demo execution") }
            return AnyView(NativeReferencedExecutionReader(host: DemoReadingHost(harness: harness),
                                                          thread: source.thread, reference: ref))
        })
        let document = ApplicationIsolatedHTML { html, failure in
            NativeApplicationHTMLSurface(source: html, thread: entry.ref, theme: theme, suppressed: false, locale: locale,
                readDocument: { _ in .init(html: JSONText(story.document), contentRevision: "brief-1") },
                openExternal: { _ in throw DemoThread.readOnly }, onBack: {}, onSettings: {},
                onNativeNavigationChange: { _ in }, onFailure: failure)
                .environment(\.nativeApplicationReadingPanel, true)
        }
        let domain = ApplicationDomainClient(pluginID: plugin.ownerPluginID) { kind, name, input, _, _ in
            guard kind == .query, input["reportId"] == .string(entry.ref.threadID) else { throw DemoThread.readOnly }
            switch name {
            case "report.cover": return .object(["html": .text(story.cover), "contentRevision": .text("cover-1")])
            case "report.relations":
                let facts = source.execution.json
                return .object(["reportId": .string(entry.ref.threadID), "revision": .integer(entry.revision),
                    "items": .array([.object(["reference": Self.referenceJSON(ref), "execution": facts,
                        "unavailable": .text(""), "bindingCount": .integer(1), "thread": .object([
                            "title": .string(source.thread.title), "archived": .bool(false),
                            "currentExecution": facts, "backgroundRunning": .bool(false)])])])])
            default: throw DemoThread.readOnly
            }
        }
        return try .init(theme: theme, locale: locale, lifetime: PluginLifetime(), domain: domain,
            capabilities: .init(scope: scope, requires: plugin.requires, registrations: [
                .init(ApplicationCapabilities.executionReferencesUI, value: references),
                .init(ApplicationCapabilities.isolatedHTML, value: document)]), openThread: { _, _ in }, openExecution: { _ in })
    }
}

struct DemoReportStory {
    let id: String
    let title: String
    let emoji: String
    let intro: String
    let label: String
    let accent: String
    let highlight: String
    let figures: [(String, String)]
    let finding: String
    let decision: String

    static let receipt = Self(id: "checkout-brief", title: "Checkout release brief", emoji: "🧾",
        intro: "One discounted basket, traced from cart to receipt.", label: "Checkout / Receipt", accent: "#a6c4b1",
        highlight: "€48.00", figures: [("Basket", "€50.00"), ("Promotion", "−€10.00"), ("Tax · 20%", "€8.00")],
        finding: "The cart, payment sheet and receipt now apply tax to the discounted subtotal. Each surface displays the same final charge.",
        decision: "Keep the first-tap check on mobile Safari on the release list before opening express checkout to more shoppers.")
    static let wallet = Self(id: "wallet-brief", title: "Wallet retry reconciliation", emoji: "💳",
        intro: "A shopper opened the wallet twice. Follow both attempts to the settled order.", label: "Checkout / Wallet", accent: "#a7bfd8",
        highlight: "1 paid order", figures: [("Wallet attempts", "2"), ("Captured charges", "1"), ("Receipts sent", "1")],
        finding: "The first authorization expired. Only the second attempt captured €48.00. The late callback matched the existing order and its receipt.",
        decision: "Keep one order reference across retries. Use the capture record to decide when to send the receipt.")
    static let refunds = Self(id: "refund-brief", title: "Where the refund cent goes", emoji: "🪙",
        intro: "Three separate returns account for every cent of a discounted order.", label: "Checkout / Refunds", accent: "#e4c1aa",
        highlight: "€20.00 returned", figures: [("Item A", "€6.66"), ("Item B", "€6.67"), ("Item C", "€6.67")],
        finding: "Three €10 items shared a €10 voucher. The first item received the extra cent of discount, so its refund came back one cent lower than the others.",
        decision: "Refund each line from the amount originally paid for it. The third return then closes the balance at €0.00.")
    static let exports = Self(id: "export-brief", title: "CSV export field notes", emoji: "📈",
        intro: "Three sample exports, with a fixed memory budget.", label: "API Platform / CSV", accent: "#acc7d9",
        highlight: "5,000 rows / batch", figures: [("10,000 rows", "2 s"), ("50,000 rows", "9 s"), ("100,000 rows", "18 s")],
        finding: "Increasing the row count tenfold raised the elapsed time from two to eighteen seconds. The stream held at most one batch at a time.",
        decision: "Use a 5,000-row batch. Keep the cursor checkpoint at the end of each written batch so an interrupted download can resume.")
    static let launch = Self(id: "launch-brief", title: "Launch desk handoff", emoji: "🗞️",
        intro: "Two announcement links are ready. One translation still needs a routing fix.", label: "Launch Desk / Proof", accent: "#dbc3a1",
        highlight: "2 of 3 ready", figures: [("Workspace link", "Ready"), ("Desktop notes", "Ready"), ("Help article", "Review")],
        finding: "The release announcement reaches the workspace and desktop notes. The help link still opens the English article from the translated email.",
        decision: "The English announcement is ready. Hold the localized send until its help link opens the translated article from a fresh workspace.")

    private var table: String {
        "<dl>" + figures.map { "<div><dt>\($0.0)</dt><dd>\($0.1)</dd></div>" }.joined() + "</dl>"
    }
    private var style: String {
        """
        *{box-sizing:border-box}body{margin:0;font:16px -apple-system,sans-serif;color:#263f37}
        dl{margin:16px 0}dl div{display:flex;justify-content:space-between;margin:7px 0}
        dd{font-variant-numeric:tabular-nums}small{font:600 11px ui-monospace,monospace;letter-spacing:.12em;text-transform:uppercase}
        """
    }
    var cover: String {
        """
        <!doctype html><meta charset="utf-8"><style>\(style)
        body{height:100vh;padding:22px 32px;background:\(accent)}article{padding:18px 22px 24px;background:#fff9e8;
        box-shadow:0 6px 12px #29473428;transform:rotate(-3deg);border-bottom:3px dotted \(accent)}
        strong{display:block;font:600 30px Georgia,serif;border-top:1px dashed #8d9b89;padding-top:9px}
        </style><article><small>\(label)</small>\(table)<strong>\(highlight)</strong></article>
        """
    }
    var document: String {
        """
        <!doctype html><html lang="en"><meta charset="utf-8"><meta name="color-scheme" content="light dark">
        <style>\(style)body{background:Canvas;color:CanvasText}main{max-width:640px;margin:0 auto;padding:52px 36px}
        h1{font:500 clamp(28px,5vw,46px) Georgia,serif;margin:12px 0}p{line-height:1.6}section{margin:24px 0;
        padding:20px 26px;border-radius:12px;background:\(accent);color:#24332c}strong{display:block;border-top:1px dashed;
        padding-top:12px}</style><main><small>Super Thread · \(label)</small><h1>\(title)</h1>
        <p>\(intro) \(finding)</p><section>\(table)<strong>\(highlight)</strong></section>
        <h2>Release decision</h2><p>\(decision)</p></main></html>
        """
    }
}

extension DemoThread {
    static var readOnly: PluginContractError { PluginContractError("This sample workspace is read-only.") }
}

@MainActor struct DemoReadingHost: NativeThreadReadingHost {
    let harness: AnyHarnessPlugin
    var draftStorageDirectory: URL? { nil }

    func readingActions(for thread: HarnessThread, routes: NativeHarnessThreadRoutes) -> HarnessThreadActions {
        .init(interrupt: { throw DemoThread.readOnly }, respond: { _ in throw DemoThread.readOnly },
              invokeHarnessExtension: { _, _ in throw DemoThread.readOnly }, forkThread: { _ in throw DemoThread.readOnly },
              openExternal: { _ in throw DemoThread.readOnly }, openFollowUp: { routes.openFollowUp?($0) })
    }

    func conversation(input: HarnessThreadInput, presentation: HarnessConversationPresentation,
                      routes: NativeHarnessThreadRoutes, onIndexChange: @escaping (ThreadConversationIndex) -> Void) -> AnyView {
        let context = HarnessRenderContext(content: .materialized, presentation: presentation,
            contentResource: { _ in .init(state: .ready(input.thread.sessionState), retry: {}, release: {}) }, onIndexChange: onIndexChange)
        do { return try harness.threadView(input: input, actions: readingActions(for: input.thread, routes: routes), context: context) }
        catch { return AnyView(Text(error.localizedDescription)) }
    }
}
