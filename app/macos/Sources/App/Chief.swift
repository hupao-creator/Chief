import AppKit
import Combine
import ChiefPluginUI
import Observation
import Darwin
import Foundation
import ChiefCore
import ChiefComposition
import ChiefUI
import SwiftUI

#if !CHIEF_WORKSPACE_LIFECYCLE_REPLAY
@main @MainActor
struct Chief {
    static func main() {
        let arguments = CommandLine.arguments
        if Bundle.main.bundleIdentifier == "com.mokusei.desktop.demo" || arguments.dropFirst().contains("--demo") {
            DemoApp.main()
            return
        }
        if arguments.count == 4, arguments[1] == "--finish-runtime", arguments[2].hasPrefix("/") {
            Task.detached {
                await NativeRuntimeExitCleanup.finish(directory: URL(fileURLWithPath: arguments[2]), epoch: arguments[3])
                exit(EXIT_SUCCESS)
            }
            dispatchMain()
        }
        WorkspaceApp.main()
    }
}
#endif

@MainActor
private struct WorkspaceApp: App {
    @State private var session = WorkspaceSession()
    var body: some Scene {
        Window("Chief", id: "workspace") {
            WorkspaceWindow(session: session)
                .frame(minWidth: NativeGeometry.minimumWindow.width, minHeight: NativeGeometry.minimumWindow.height)
        }
        .nativeWorkspaceWindowStyle()
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: session.benchmarkOverview ? 1280 : NativeGeometry.initialWindow.width,
                     height: session.benchmarkOverview ? 820 : NativeGeometry.initialWindow.height)
        .restorationBehavior(session.benchmarkOverview ? .disabled : .automatic)
        .defaultWindowPlacement { _, _ in
            session.benchmarkOverview ? WindowPlacement(CGPoint(x: 50, y: 60), size: CGSize(width: 1280, height: 820)) : WindowPlacement()
        }
        .commands {
            NativeWorkspaceCommands(locale: session.locale)
            CommandGroup(replacing: .help) {
                Button(session.locale.text("打开演示工作区", "Open Demo Workspace")) {
                    Task {
                        do { try await DemoApp.open() }
                        catch { session.error = error.localizedDescription }
                    }
                }
                Link(session.locale.text("Chief 使用指南（英文）", "Chief User Guide"),
                     destination: URL(string: "https://github.com/hupao-creator/Chief/blob/main/docs/README.md")!)
                    .keyboardShortcut("?")
            }
            CommandGroup(replacing: .appTermination) {
                Button(session.locale.text("退出", "Quit")) { session.quit() }.keyboardShortcut("q").disabled(session.resetting)
            }
            CommandGroup(after: .toolbar) {
                Button(session.locale.text("重新载入", "Reload")) { session.performWebCommand("chiefReloadFocusedWebContent:") { session.reload() } }.keyboardShortcut("r").disabled(session.busy)
                Button(session.locale.text("实际大小", "Actual Size")) { session.performWebCommand("chiefResetFocusedWebContentZoom:") }.keyboardShortcut("0")
                Button(session.locale.text("放大", "Zoom In")) { session.performWebCommand("chiefZoomInFocusedWebContent:") }.keyboardShortcut("+")
                Button(session.locale.text("缩小", "Zoom Out")) { session.performWebCommand("chiefZoomOutFocusedWebContent:") }.keyboardShortcut("-")
            }
        }
    }
}

@MainActor @Observable
final class WorkspaceSession {
    private(set) var benchmarkOverview = false
    private(set) var benchmarkEmojiGlass = false
    private(set) var locale = DesktopLocale.system
    var model: NativeWorkspaceModel?
    var presentation: NativeWorkspacePresentation?
    var error: String?
    var quitSettingsBlocked = false
    var busy = false
    var generation = UUID()
    private var lease: RuntimeProfileClientLease?
    private var options: LaunchOptions?
    private(set) var resetting = false
    private var exitCleanup: NativeRuntimeExitCleanup?
    private var interactionServer: NativeInteractionServer?
    private var launchReceipt: URL?
    private var task: Task<Void, Never>?
    private(set) var reloadTask: Task<Void, Never>?
    private var operationID: UUID?
    private var quitting = false
    private var finishingQuit = false
    private var quitSavingSettings = false
    private var quitDeadline: Task<Void, Never>?
    init() {
        do {
            let options = try LaunchOptions()
            launchReceipt = options.launchReceipt
            benchmarkOverview = options.benchmarkOverview
            benchmarkEmojiGlass = options.benchmarkEmojiBadge == "liquid-glass"
            let lease = try RuntimeProfileClientLease(dataDirectory: options.dataDirectory)
            if try lease.profile.hasPendingFactoryReset() {
                guard let runtime = options.launch?.executable else {
                    throw RuntimeError("RESET_FAILED", "Reopen Chief with its Runtime to finish resetting this profile.")
                }
                let profile = lease.profile
                resetting = true
                task = Task {
                    defer { resetting = false }
                    do {
                        try await Task.detached { try NativeFactoryReset.finish(profile: profile, runtime: runtime) }.value
                        try open(options, lease: RuntimeProfileClientLease(dataDirectory: profile.dataDirectory))
                        start()
                    } catch {
                        self.error = locale.text("重置未完成。请处理以下问题，然后重新打开 Chief。", "Reset did not finish. Resolve the issue below and reopen Chief.") + "\n" + error.localizedDescription
                    }
                }
            } else {
                try open(options, lease: lease)
            }
        } catch { self.error = error.localizedDescription }
    }

    private func open(_ options: LaunchOptions, lease: RuntimeProfileClientLease) throws {
        // Another confirming client may have won admission between maintenance and reopen.
        guard try !lease.profile.hasPendingFactoryReset() else {
            throw RuntimeError("PROFILE_MAINTENANCE", "Reopen Chief to finish the pending factory reset.")
        }
        self.options = options
        self.lease = lease
        lease.retainForProcess()
        let profile = lease.profile
        NativeTypography.registerFonts()
        let preferences = DesktopPreferences(directory: profile.dataDirectory)
        // Explicit scenario setup belongs to the application. External runners
        // never synthesize preference files or bypass the production renderer.
        if options.benchmarkOverview {
            try preferences.setOnboardingCompleted(true)
            let receipt: [String: Any] = ["version": 1, "scenario": "overview",
                "pid": ProcessInfo.processInfo.processIdentifier, "agentEmojiBadge": options.benchmarkEmojiBadge,
                "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                "increaseContrast": NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast]
            try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
                .write(to: profile.dataDirectory.appendingPathComponent("benchmark-scenario.json"), options: .atomic)
        }
        let client = RuntimeClient(profile: profile, launch: options.launch)
        let composition = try NativePlugins.make()
        let model = NativeWorkspaceModel(client: client, preferences: preferences, plugins: composition, locale: locale)
        if let path = options.automationSocket {
            interactionServer = try NativeInteractionServer(path: path) { [weak self] in
                guard let self, !self.busy else { return nil }
                return self.presentation
            }
        }
        self.model = model; presentation = NativeWorkspacePresentation(workspace: model)
        if let executable = Bundle.main.executableURL { exitCleanup = NativeRuntimeExitCleanup(profile: profile, executable: executable) }
    }
    #if CHIEF_WORKSPACE_LIFECYCLE_REPLAY
    init(model: NativeWorkspaceModel) {
        self.model = model
        locale = model.locale
        presentation = NativeWorkspacePresentation(workspace: model)
    }
    #endif
    func refreshSystemLocale() {
        let value = DesktopLocale.system
        guard locale != value else { return }
        locale = value
        model?.updateSystemLocale(value)
    }

    func start() {
        guard let model else { return }
        model.start()
        if let launchReceipt {
            do {
                let data = try JSONSerialization.data(withJSONObject: ["pid": ProcessInfo.processInfo.processIdentifier])
                try data.write(to: launchReceipt, options: .atomic)
            } catch { self.error = error.localizedDescription }
            self.launchReceipt = nil
        }
    }
    func performWebCommand(_ selector: String, fallback: () -> Void = {}) {
        if !NSApp.sendAction(NSSelectorFromString(selector), to: nil, from: nil) { fallback() }
    }
    func requestFactoryReset() {
        guard !busy, !quitting, let model, model.settingsOpen, let window = NSApp.keyWindow,
              window.attachedSheet == nil else { return }
        NativeFactoryReset.confirm(in: window, locale: locale) { [weak self] confirmed in
            guard confirmed else { return }
            self?.beginFactoryReset()
        }
    }

    private func beginFactoryReset() {
        guard !busy, !quitting, let model, model.settingsOpen, let lease else { return }
        guard model.runtimeAvailable, let runtime = options?.launch?.executable else {
            error = locale.text("请连接 Chief 后台服务，然后重试。", "Connect to Chief’s Runtime, then try again.")
            return
        }
        do { try lease.reserveForFactoryReset() }
        catch { self.error = error.localizedDescription; return }
        exitCleanup?.captureEpoch()
        busy = true
        resetting = true
        task = Task {
            do {
                guard let owner = try lease.profile.readConnection() else {
                    throw RuntimeError("RESET_FAILED", "Chief’s Runtime is unavailable.")
                }
                _ = try await model.invoke("history:prepare-reset")
                try lease.profile.requestFactoryReset(epoch: owner.epoch)
                try await model.stop()
                exitCleanup?.disarm()
                guard try lease.profile.hasPendingFactoryReset() else {
                    throw RuntimeError("RESET_FAILED", "The retiring Runtime did not commit the reset.")
                }
                interactionServer?.stop()
                try NativeFactoryReset.restart(profile: lease.profile, runtime: runtime, socket: options?.automationSocket)
            } catch {
                // Drain can fail after fencing the generation. Never return a
                // half-retired workspace to the user or report reset success.
                self.model = nil
                presentation = nil
                self.error = locale.text("重置未完成。退出并重新打开 Chief 后重试。", "Reset did not finish. Quit and reopen Chief to retry.") + "\n" + error.localizedDescription
                busy = false
                resetting = false
            }
        }
    }

    func reload() {
        guard !busy, !quitting, let model else { return }
        model.resetSettingsForReload()
        let retiring = presentation
        replacePresentation(for: model) {
            await retiring?.release()
            await model.harnessHost.releaseAll()
        }
    }
    private func replacePresentation(for model: NativeWorkspaceModel, after cleanup: @escaping @MainActor () async -> Void) {
        let operationID = UUID()
        self.operationID = operationID
        busy = true
        let pending = Task {
            defer {
                if self.operationID == operationID {
                    self.operationID = nil; reloadTask = nil; task = nil; busy = false
                }
            }
            // Cancellation revokes publication, not the scoped resource drain.
            // A rejected Quit joins this same retirement before restoring a UI owner.
            await cleanup()
            guard !Task.isCancelled, self.operationID == operationID, !quitting else { return }
            model.settingsOpen = false
            presentation = NativeWorkspacePresentation(workspace: model); generation = UUID()
        }
        reloadTask = pending
        task = pending
    }
    func quit(discardSettings: Bool = false) {
        guard !resetting else { return }
        guard !quitting else {
            NativeProcessExit.forceExit { exitCleanup?.prepareForExit() }
        }
        quitting = true; busy = true
        let operationID = UUID()
        self.operationID = operationID
        quitSavingSettings = !discardSettings
        if model != nil { exitCleanup?.captureEpoch() }
        task?.cancel()
        // Network cleanup can outlive cancellation. The deadline must
        // not join that work; the epoch-fenced exit helper finishes it instead.
        quitDeadline = Task {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard !Task.isCancelled, self.operationID == operationID, quitting else { return }
            if quitSavingSettings {
                rejectQuitForSettings(RuntimeError("SETTINGS_UNSAVED", "Saving settings timed out."))
                return
            }
            finishQuit()
        }
        task = Task {
            if !discardSettings {
                do { try await model?.settingsModel.draft.flushForQuit() }
                catch {
                    guard !Task.isCancelled, self.operationID == operationID, quitting else { return }
                    rejectQuitForSettings(error)
                    return
                }
            }
            guard !Task.isCancelled, self.operationID == operationID, quitting else { return }
            quitSavingSettings = false
            do {
                try await model?.stop()
                exitCleanup?.disarm()
            } catch {}
            finishQuit()
        }
    }
    private func rejectQuitForSettings(_ error: Error) {
        quitDeadline?.cancel(); quitDeadline = nil
        task?.cancel(); task = nil
        operationID = nil
        quitting = false; quitSavingSettings = false; busy = false
        quitSettingsBlocked = true
        self.error = locale.text(
            "设置尚未保存。可以继续编辑，或不保存并退出。\n\(error.localizedDescription)",
            "Settings have not been saved. Keep editing, or quit without saving.\n\(error.localizedDescription)")
        if let reloadTask, let model {
            // Keep the failed Settings draft; restarting Reload would discard it.
            replacePresentation(for: model) { await reloadTask.value }
        }
    }
    private func finishQuit() {
        // A late cleanup completion cannot start a second process-exit sequence.
        guard !finishingQuit else { return }
        finishingQuit = true
        quitDeadline?.cancel()
        NativeProcessExit.forceExit {
            exitCleanup?.prepareForExit()
            interactionServer?.stop()
        }
    }
}

private extension UserDefaults {
    // Observe the OS key through KVO, which receives changes from other processes.
    @objc(AppleLanguages) dynamic var preferredInterfaceLanguages: [String]? { stringArray(forKey: "AppleLanguages") }
}

struct WorkspaceWindow: View {
    let session: WorkspaceSession
    var body: some View {
        Group {
            if session.resetting {
                ProgressView(session.locale.text("正在恢复出厂设置…", "Resetting Chief…"))
            } else if let model = session.model, let presentation = session.presentation {
                NativeWorkspaceView(model: model, presentation: presentation).id(session.generation)
                    .environment(\.agentThreadEmojiUsesLiquidGlass, session.benchmarkEmojiGlass)
                    .environment(\.requestFactoryReset, session.requestFactoryReset)
            } else {
                ContentUnavailableView(session.locale.text("无法打开 Chief", "Unable to open Chief"),
                    systemImage: "exclamationmark.triangle", description: Text(session.error ?? ""))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(session.busy)
        .modifier(NativeWorkspaceWindowSurface())
        .environment(\.locale, Locale(identifier: session.locale.rawValue))
        .onAppear { session.refreshSystemLocale(); session.start() }
        .onReceive(UserDefaults.standard.publisher(for: \.preferredInterfaceLanguages).receive(on: RunLoop.main)) { _ in
            session.refreshSystemLocale()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification).receive(on: RunLoop.main)) { _ in
            session.refreshSystemLocale()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            session.refreshSystemLocale()
        }
        .onDisappear { session.quit() }
        .alert("Chief", isPresented: Binding(get: { session.error != nil && session.model != nil }, set: { if !$0 { session.error = nil } })) {
            if session.quitSettingsBlocked {
                Button(session.locale.text("继续编辑", "Keep Editing"), role: .cancel) {
                    session.error = nil; session.quitSettingsBlocked = false
                }
                Button(session.locale.text("不保存并退出", "Quit Without Saving"), role: .destructive) {
                    session.error = nil; session.quitSettingsBlocked = false; session.quit(discardSettings: true)
                }
            } else { Button(session.locale.text("好", "OK")) { session.error = nil } }
        } message: { Text(session.error ?? "") }
    }
}

private struct LaunchOptions {
    let dataDirectory: URL
    let launch: RuntimeLaunchConfiguration?
    let automationSocket: String?
    let launchReceipt: URL?
    let explicitDataDirectory: Bool
    let benchmarkOverview: Bool
    let benchmarkEmojiBadge: String

    init() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        var options: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            if flag.hasPrefix("-psn_") { index += 1; continue }
            let allowedValues: [String: [String]] = ["--benchmark-scenario": ["overview"],
                "--benchmark-agent-emoji-badge": ["flat", "liquid-glass"]]
            guard (allowedValues[flag] != nil || ["--data-dir", "--runtime", "--automation-socket", "--launch-receipt"].contains(flag)),
                  index + 1 < arguments.count, options[flag] == nil,
                  allowedValues[flag].map({ $0.contains(arguments[index + 1]) }) ?? arguments[index + 1].hasPrefix("/") else {
                throw NSError(domain: "ChiefLaunch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown launch argument: \(flag)"])
            }
            options[flag] = arguments[index + 1]
            index += 2
        }
        automationSocket = options["--automation-socket"]
        launchReceipt = options["--launch-receipt"].map { URL(fileURLWithPath: $0) }
        explicitDataDirectory = options["--data-dir"] != nil
        benchmarkOverview = options["--benchmark-scenario"] == "overview"
        benchmarkEmojiBadge = options["--benchmark-agent-emoji-badge"] ?? "flat"
        if options["--benchmark-agent-emoji-badge"] != nil, !benchmarkOverview {
            throw NSError(domain: "ChiefLaunch", code: 6,
                          userInfo: [NSLocalizedDescriptionKey: "Badge experiments require --benchmark-scenario overview."])
        }
        if benchmarkOverview, !explicitDataDirectory || automationSocket == nil {
            throw NSError(domain: "ChiefLaunch", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Benchmark scenarios require explicit --data-dir and --automation-socket."])
        }
        if automationSocket != nil, options["--data-dir"] == nil {
            throw NSError(domain: "ChiefLaunch", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Automation requires an explicit --data-dir."])
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dataDirectoryName = Bundle.main.object(forInfoDictionaryKey: "ChiefDataDirectoryName") as? String
            ?? "Chief"
        dataDirectory = options["--data-dir"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? RuntimeProfile.defaultDataDirectory(home: home, name: dataDirectoryName)
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let runtime = options["--runtime"].map { URL(fileURLWithPath: $0) }
            ?? executableDirectory?.appendingPathComponent("chief-runtime")
        if let runtime, FileManager.default.isExecutableFile(atPath: runtime.path) {
            launch = RuntimeLaunchConfiguration(executable: runtime, workingDirectory: home)
        } else {
            if options["--runtime"] != nil || Bundle.main.bundleURL.pathExtension == "app" {
                throw NSError(domain: "ChiefLaunch", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "The native application requires its Go runtime executable."])
            }
            // A development executable may explicitly connect to an existing service.
            // It never silently falls back to a machine-specific runtime or production profile.
            launch = nil
        }
    }
}
