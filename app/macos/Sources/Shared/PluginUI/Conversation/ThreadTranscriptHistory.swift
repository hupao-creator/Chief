import ChiefCore
import ChiefPluginAPI
import SwiftUI

/// Unscoped inherited transcripts have no live execution or actionable form.
package struct ThreadTranscriptHistory: View {
    let id: JSONText
    let items: [ThreadTranscriptItem]
    let createdAt: Double
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    @Environment(\.threadAgentDetail) private var agentDetail
    @Environment(\.threadDetailVisibility) private var visibility
    @Environment(\.locale) private var locale

    package init(id: JSONText, items: [ThreadTranscriptItem], createdAt: Double,
                 actions: HarnessThreadActions, context: HarnessRenderContext) {
        self.id = id
        self.items = items
        self.createdAt = createdAt
        self.actions = actions
        self.context = context
    }

    package var body: some View {
        let layout = ThreadTranscriptLayout(items, agentDetail: agentDetail, target: visibility.messageAnchorID, inheritedTurns: true)
        ThreadDetailTurn(id: id, rows: layout.detailRows(executionID: id, workVisible: visibility.work,
            actions: actions, context: context), createdAt: createdAt, updatedAt: createdAt,
            status: NativePluginLocalization.localize("只读历史", locale: locale), active: false,
            showsSteerMessages: true, workAvailable: layout.hasWork())
    }
}

package struct ThreadBackgroundWork: View {
    package struct Item {
        let id: JSONText
        let label: String
        let detail: String?
        let status: String
        package init(id: JSONText, label: String, detail: String? = nil, status: String) {
            self.id = id
            self.label = label
            self.detail = detail
            self.status = status
        }
    }

    let id: JSONText
    let title: String
    let items: [Item]
    @Environment(\.locale) private var locale
    @Environment(\.threadAgentDetail) private var agentDetail
    @Environment(\.threadDetailVisibility) private var visibility

    package init(id: JSONText, title: String, items: [Item]) {
        self.id = id
        self.title = title
        self.items = items
    }

    package var body: some View {
        Group {
            if !agentDetail || visibility.work {
                VStack(alignment: .leading, spacing: 12) {
                    let failed = items.filter { $0.status == "failed" }.count
                    HStack(spacing: 8) {
                        NativeIcon(name: "Terminal", size: 14)
                        Text(NativePluginLocalization.localize(title, locale: locale)
                             + (agentDetail ? " · \(items.count.formatted(.number.locale(locale)))" : "")
                             + (failed > 0 ? " · \(failed) " + NativePluginLocalization.localize("失败", locale: locale) : ""))
                    }.foregroundStyle(NativePalette.thread.muted.swiftUI)
                    if !agentDetail {
                        ForEach(items, id: \.id) { item in
                            HStack(alignment: .top, spacing: 8) {
                                if item.status == "running" { NativeStatusSpinner(size: 12) }
                                else { NativeIcon(name: item.status == "failed" ? "CircleAlert" : "Check", size: 12) }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.label).font(.system(size: 11, design: .monospaced))
                                    if let detail = item.detail { Text(detail).foregroundStyle(NativePalette.thread.muted.swiftUI) }
                                }.lineLimit(1)
                            }
                        }
                    }
                }.font(NativeTypography.inter(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16).overlay(alignment: .top) { Rectangle().fill(NativePalette.thread.lineSoft.swiftUI).frame(height: 1) }.padding(.top, 24)
            }
        }.preference(key: ThreadWorkPreference.self, value: [id: !items.isEmpty])
    }
}
