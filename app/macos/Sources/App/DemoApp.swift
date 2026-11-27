import AppKit
import ChiefComposition
import ChiefPluginUI
import ChiefUI
import SwiftUI

/// Selected in main before constructing WorkspaceApp or admitting a Runtime profile.
@MainActor
struct DemoApp: App {
    @NSApplicationDelegateAdaptor(DemoDelegate.self) private var delegate
    private let locale = DesktopLocale.system

    init() { NativeTypography.registerFonts() }

    var body: some Scene {
        Window("Chief", id: "sample-workspace") {
            DemoWorkspace()
                .modifier(NativeWorkspaceWindowSurface())
                .frame(minWidth: NativeGeometry.minimumWindow.width, minHeight: NativeGeometry.minimumWindow.height)
        }
        .nativeWorkspaceWindowStyle()
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: NativeGeometry.initialWindow.width, height: NativeGeometry.initialWindow.height)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button(locale.text("退出演示", "Exit Demo")) { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .restorationBehavior(.disabled)
    }

    static func open() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--demo"]
        configuration.createsNewApplicationInstance = true
        _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
    }
}

private final class DemoDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
