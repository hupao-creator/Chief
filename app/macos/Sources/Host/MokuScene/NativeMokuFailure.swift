import ChiefCore
import SwiftUI

struct NativeMokuFailure: Equatable, Sendable {
    enum Reason: String {
        case connection, host, startup, execution, authentication
        case rateLimit = "rate-limit"
    }
    let owner: JSONText
    let id: JSONText
    let reason: Reason
    let state: String

    init?(_ row: JSONValue, owner: JSONText, id: JSONText) {
        guard let code = row["failureCode"]?.stringValue, let reason = Reason(rawValue: code),
              let state = row["resendState"]?.stringValue else { return nil }
        self.owner = owner; self.id = id; self.reason = reason; self.state = state
    }

    init?(_ row: JSONValue) {
        guard case .string(let owner) = row["threadId"], case .string(let id) = row["failureId"] else { return nil }
        self.init(row, owner: owner, id: id)
    }

    func text(chinese: Bool) -> String {
        switch reason {
        case .authentication: chinese ? "模型服务未通过身份验证。请检查 Host 的登录状态或 API 密钥后重发。" : "The model service rejected authentication. Check the host account or API key, then resend."
        case .rateLimit: chinese ? "模型服务已达到请求频率上限。请稍后重发。" : "The model service reached its request limit. Wait a moment, then resend."
        case .connection: chinese ? "与 Codex 的连接中断，重新连接失败。" : "Chief lost its connection to Codex and could not reconnect."
        case .startup: chinese ? "Chief 无法启动 Host 会话。请检查设置中的 Host 后重发。" : "Chief could not open its host session. Check the host in Settings, then resend."
        case .host: chinese ? "当前 Host 或模型不可用。请在设置中选择可用的配置后重发。" : "Choose an available host or model in Settings, then resend."
        case .execution: chinese ? "Chief 在完成回复前停止了。运行服务未返回可显示的原因。" : "Chief stopped before finishing its reply. No further details are available."
        }
    }
}

struct NativeMokuFailureContent: View {
    let failure: NativeMokuFailure
    let workspace: NativeWorkspaceModel?
    let chinese: Bool
    var fillsBar = false
    @State private var sending = false
    @State private var declined = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 1, green: 0.77, blue: 0.49))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: failure.text(chinese: chinese))
                        .accessibilityIdentifier("moku-failure-reason")
                    if declined && failure.state == "ready" {
                        Text(chinese ? "重发未获确认" : "Resend unconfirmed")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: fillsBar ? .infinity : nil, alignment: .leading)

            if failure.state == "ready", let workspace {
                Button {
                    guard !sending else { return }
                    sending = true; declined = false
                    Task { @MainActor in
                        defer { sending = false }
                        do {
                            _ = try await workspace.invoke("moku:resend", args: [.object([
                                "threadId": .string(failure.owner), "failureId": .string(failure.id)
                            ])])
                        } catch { declined = true }
                    }
                } label: {
                    Label(sending ? (chinese ? "正在重发" : "Resending") : (chinese ? "重发" : "Resend"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                .fixedSize()
                .disabled(sending || !workspace.runtimeAvailable || workspace.catalog.moku?.id != failure.owner ||
                          workspace.catalog.moku?.observation.backgroundWork != nil ||
                          [.running, .waitingForUser].contains(workspace.catalog.moku?.observation.latestExecution?.status))
                .accessibilityIdentifier("moku-failure-resend")
            } else if failure.state == "sent" || failure.state == "unconfirmed" {
                Text(failure.state == "sent" ? (chinese ? "已重发" : "Resent") : (chinese ? "重发尚未确认" : "Resend unconfirmed"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(chinese ? "Chief 未能完成请求" : "Chief couldn’t finish")
        .accessibilityIdentifier("moku-failure-message")
    }
}
