import AppKit
import ChiefPluginAPI
@testable import ChiefPluginUI
@testable import ChiefUI

extension ReportFollowup {
    static func recordIdentity(window: NSWindow, host: NativeWorkspacePresentation, report: ApplicationThreadRef,
                               source: ApplicationExecutionRef, scenario: String) async throws {
        let scene = host.scene
        let movie = try await DockMovieCapture(window: window, folder: scenario)
        let start = CACurrentMediaTime()
        var events = [[String: Any]]()
        func record(_ name: String) {
            events.append(["action": name, "seconds": CACurrentMediaTime() - start,
                           "inputReady": scene.inputInteractionReady, "width": scene.capsuleFrame.width])
        }
        func editorReady() async throws {
            try await wait("Report editor did not settle") {
                host.dockExecution == source && scene.inputOpen && scene.inputInteractionReady && scene.capsuleFrame.midX > 800
            }
            try await Task.sleep(for: .milliseconds(650))
        }
        for reverse in (scenario == "identity" ? [false, true] : [false]) {
            host.open(report)
            try await wait("Missing Report list") { host.reportSidecards.active == .relatedExecutions }
            try await Task.sleep(for: .milliseconds(450))
            record("select source")
            host.reportSidecards.selectExecution(source)
            try await editorReady()
            record("press Report Close")
            try pressReadingPanelClose(in: window, identifier: "report-reading-panel-frame")
            if reverse {
                try await wait("Report did not begin closing") { scene.readingPanelReturning }
                try await Task.sleep(for: .milliseconds(650))
                guard scene.readingPanelReturning else { throw PluginContractError("Missed in-flight Close") }
                record("reopen Report")
                host.open(report)
                try await editorReady()
                record("press Report Close again")
                try pressReadingPanelClose(in: window, identifier: "report-reading-panel-frame")
            }
            try await wait("Close did not return to Overview") { host.selected == nil && scene.overviewVisible }
            try await Task.sleep(for: .milliseconds(1000))
            record("Overview settled")
        }
        try await movie.finish()
        try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
            .write(to: movie.directory.appendingPathComponent("events.json"))
    }
}
