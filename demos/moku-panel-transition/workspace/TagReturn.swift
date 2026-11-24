import AppKit
import ChiefPluginAPI
@testable import ChiefUI

extension ReportFollowup {
    static func recordTagReturn(window: NSWindow, host: NativeWorkspacePresentation,
                                report: ApplicationThreadRef, scenario: String) async throws {
        let controls = host.overview.chromeInteractions
        // The fixture's Inbox tag has three status buttons in the left rail.
        func filtersAvailable() -> Bool {
            !controls.mountedIDs(in: .semantic).isEmpty && controls.mountedIDs(in: .status).count == 3
        }
        try await wait("Tagged Overview did not mount") {
            filtersAvailable() && host.canvas.visibleFrame(for: report.threadID.string) != nil
        }
        try await Task.sleep(for: .milliseconds(700))
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
    }
}
