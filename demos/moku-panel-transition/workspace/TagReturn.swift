import AppKit
import ChiefPluginAPI
@testable import ChiefUI

extension ReportFollowup {
    static func recordTagReturn(window: NSWindow, host: NativeWorkspacePresentation,
                                report: ApplicationThreadRef, scenario: String) async throws {
        let controls = host.overview.chromeInteractions
        func filtersAvailable() -> Bool {
            !controls.mountedIDs(in: .semantic).isEmpty && Set(controls.mountedIDs(in: .status)) == ["running", "unread", "all", "completed"]
        }
        try await wait("Tagged Overview did not mount") {
            filtersAvailable() && host.canvas.visibleFrame(for: report.threadID.string) != nil
        }
        try await Task.sleep(for: .milliseconds(700))
        func statusFrame(in node: NSObject) -> CGRect? {
            func attribute(_ key: String) -> Any? {
                node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil
            }
            if attribute("accessibilityIdentifier") as? String == "overview-status-all",
               attribute("accessibilityRole") as? String == NSAccessibility.Role.button.rawValue,
               let frame = attribute("accessibilityFrame") as? NSValue {
                return window.convertFromScreen(frame.rectValue)
            }
            let children = attribute("accessibilityChildren") as? [NSObject] ?? []
            return children.lazy.compactMap { statusFrame(in: $0) }.first
        }
        guard let frame = statusFrame(in: window) ?? window.contentView.flatMap({ statusFrame(in: $0) }) else {
            throw PluginContractError("Missing mounted All statuses button")
        }
        let movie = try await DockMovieCapture(window: window, folder: scenario)
        let start = CACurrentMediaTime()
        var events = [[String: Any]]()
        func record(_ action: String) {
            events.append(["action": action, "seconds": CACurrentMediaTime() - start])
        }
        func close() throws {
            record("close")
            try pressReadingPanelClose(in: window, identifier: "report-reading-panel-frame")
        }
        for reverse in [false, true] {
            try await Task.sleep(for: .milliseconds(500))
            record("open")
            host.open(report)
            try await wait("Report list did not open") { host.reportSidecards.active == .relatedExecutions }
            try await Task.sleep(for: .milliseconds(450))
            try close()
            try await wait("Missing return travel") { host.messageMotion.parentTravel?.returning == true }
            if reverse {
                try await Task.sleep(for: .milliseconds(220))
                guard host.messageMotion.parentTravel?.returning == true, !controls.hasButtons else {
                    throw PluginContractError("Expected an in-flight return with filters unavailable")
                }
                record("reopen")
                host.open(report)
                try await Task.sleep(for: .milliseconds(700))
                guard host.selected == report, !host.messageMotion.active, !controls.hasButtons else {
                    throw PluginContractError("Interrupted Close released the reader or its input")
                }
                try close()
            }
            try await wait("Overview filters did not regain input") { host.selected == nil && filtersAvailable() }
            record("overview")
        }
        try await Task.sleep(for: .milliseconds(650))
        try await movie.finish()
        try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
            .write(to: movie.directory.appendingPathComponent("events.json"))
        let geometry = ["statusCenterY": window.frame.height - frame.midY]
        try JSONSerialization.data(withJSONObject: geometry)
            .write(to: movie.directory.appendingPathComponent("filter-geometry.json"))
    }
}
