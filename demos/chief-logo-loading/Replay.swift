import AppKit
import ScreenCaptureKit
import SwiftUI
import ChiefCore
import ChiefHarnessCodex
import ChiefPluginAPI
@testable import ChiefUI

@main @MainActor private struct LoadingReplay: App {
    let model: NativeWorkspaceModel
    let presentation: NativeWorkspacePresentation
    let scenario = CommandLine.arguments.dropFirst().first ?? "--empty"
    @State private var reduced = false
    @State private var light = false

    init() {
        do {
            try prepareIsolatedNativeReplay()
            let directory = URL(filePath: FileManager.default.currentDirectoryPath).appending(path: "profile" + scenario)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let preferences = DesktopPreferences(directory: directory)
            try preferences.setOnboardingCompleted(scenario != "--onboarding")
            try preferences.selectOverviewSpace(.init(tag: "Fixture", kind: .directory, scope: "/fixture", runningTag: true))
            model = try NativeWorkspaceModel(client: RuntimeClient(profile: RuntimeProfile(dataDirectory: directory)),
                preferences: preferences,
                plugins: .init(harnesses: [AnyHarnessPlugin(CodexHarnessPlugin())], sidecards: [], applications: []),
                locale: .english)
            presentation = NativeWorkspacePresentation(workspace: model)
        } catch { fatalError(String(describing: error)) }
    }

    var body: some Scene {
        Window("Chief", id: "loading-replay") {
            NativeWorkspaceView(model: model, presentation: presentation)
                .background(light ? Color(white: 0.94) : Color(white: 0.15))
                .preferredColorScheme(light ? .light : .dark)
                .environment(\._accessibilityReduceMotion, reduced)
                .modifier(NativeWorkspaceWindowSurface())
                .environment(\.accessibilityEnabled, true)
                .task {
                    do { try await replay(); exit(0) }
                    catch { print(error); exit(1) }
                }
        }
        .nativeWorkspaceWindowStyle()
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 900, height: 560)
        .restorationBehavior(.disabled)
    }

    private func replay() async throws {
        try await Task.sleep(for: .milliseconds(500))
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "loading-replay" }) else {
            throw CocoaError(.coderValueNotFound)
        }
        let size = scenario == "--reduced" ? NSSize(width: 680, height: 480) : NSSize(width: 900, height: 560)
        window.setContentSize(size)
        window.collectionBehavior = [.auxiliary, .canJoinAllSpaces]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        try await Task.sleep(for: .milliseconds(550))
        let available = try await SCShareableContent.currentProcess
        guard let target = available.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw CocoaError(.fileReadUnknown)
        }
        let directory = URL(filePath: FileManager.default.currentDirectoryPath).appending(path: "evidence")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filter = SCContentFilter(desktopIndependentWindow: target)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * 2)
        config.height = Int(window.frame.height * 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.ignoreShadowsSingleWindow = true
        config.showsCursor = false
        func capture(_ name: String) async throws {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: directory.appending(path: name + ".png"))
        }
        if scenario != "--empty" {
            reduced = scenario == "--reduced"
            light = reduced
            try await Task.sleep(for: .milliseconds(120))
            try await capture("before")
            try await admit()
            try await Task.sleep(for: .milliseconds(100))
            try await capture("first")
            try await Task.sleep(for: .milliseconds(650))
            try await capture("settled")
            let labels = accessibilityStrings(window)
            let hasEmptyTitle = labels.contains("No running conversations")
            guard hasEmptyTitle == reduced else { throw CocoaError(.coderInvalidValue) }
            switch scenario {
            case "--populated":
                guard presentation.overview.items.count == 1, labels.contains("Replay task") else { throw CocoaError(.coderInvalidValue) }
            case "--onboarding":
                guard labels.contains("Step 1 of 5"), presentation.onboarding.blocksWorkspace else { throw CocoaError(.coderInvalidValue) }
            case "--error":
                guard model.connectionError != nil, labels.contains("Reconnect") else { throw CocoaError(.coderInvalidValue) }
            case "--landing":
                guard presentation.moku.landing, labels.contains("Type a message…") else { throw CocoaError(.coderInvalidValue) }
            case "--reduced":
                guard try artworkSample("first", in: directory).pixels == artworkSample("settled", in: directory).pixels else {
                    throw CocoaError(.coderInvalidValue)
                }
            default: throw CocoaError(.coderInvalidValue)
            }
            try Data(labels.joined(separator: "\n").utf8).write(to: directory.appending(path: "result.txt"))
            return
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let settings = SCRecordingOutputConfiguration()
        settings.outputURL = directory.appending(path: "window.mp4")
        settings.outputFileType = .mp4
        let (done, continuation) = AsyncThrowingStream<Void, Error>.makeStream()
        let observer = RecordingObserver(continuation)
        let output = SCRecordingOutput(configuration: settings, delegate: observer)
        try stream.addRecordingOutput(output)
        try await capture("loading")
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(7))
        reduced = true
        try await Task.sleep(for: .milliseconds(300))
        try await capture("reduced")
        try await Task.sleep(for: .milliseconds(950))
        try await capture("reduced-later")
        light = true
        try await Task.sleep(for: .milliseconds(350))
        try await capture("light")
        reduced = false
        try await Task.sleep(for: .seconds(1))
        try await capture("resumed")
        light = false
        try await Task.sleep(for: .seconds(3))

        try await capture("before-admission")
        try await admit()
        try await Task.sleep(for: .milliseconds(180))
        try await capture("settling")
        try await Task.sleep(for: .milliseconds(1050))
        try await capture("overview")
        try await stream.stopCapture()
        for try await _ in done {}
        let labels = accessibilityStrings(window)
        guard labels.contains("No running conversations") else {
            throw CocoaError(.coderValueNotFound)
        }
        try verifyCaptures(in: directory)
    }

    private func admit() async throws {
        if scenario == "--error" {
            await model.installPrepared(.null, event: .snapshot(.null, authority: UUID()))
            return
        }
        let chief = try HarnessThread(id: "moku", harnessID: "codex", revision: 0, sessionState: .null,
            observation: .init(), cwd: "/fixture", settings: .object([:]), createdAt: 1, updatedAt: 2,
            title: "Chief", tags: [], moku: true, transcript: .array([]))
        var threads = [chief.json]
        if scenario != "--onboarding" && scenario != "--landing" {
            let execution = scenario == "--populated" ? try PublicExecution(executionID: "run", status: .running, startedAt: 1) : nil
            threads.append(try HarnessThread(id: "task", harnessID: "codex", revision: 0, sessionState: .null,
                observation: .init(latestExecution: execution), cwd: "/fixture", settings: .object([:]),
                createdAt: 1, updatedAt: 2, title: "Replay task", tags: [], directoryTag: "Fixture", directoryScope: "/fixture").json)
        }
        let snapshot: JSONValue = .object(["revision": .integer(1), "settingsRevision": .integer(0),
            "defaultCwd": .text("/fixture"), "settings": .object([:]), "threads": .array(threads), "executions": .array([]),
            "applicationThreads": .array([])])
        await model.installPrepared(snapshot, event: .snapshot(snapshot, authority: UUID()))
        guard model.hasInitialContent, !model.waitingForInitialCatalog else { throw CocoaError(.coderInvalidValue) }
    }
}

@MainActor private func accessibilityStrings(_ value: Any) -> [String] {
    guard let node = value as? NSObject else { return [] }
    func attribute(_ key: String) -> Any? {
        node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil
    }
    return ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].compactMap { attribute($0) as? String }
        + (attribute("accessibilityChildren") as? [Any] ?? []).flatMap { accessibilityStrings($0) }
}

// Compare only the artwork region. Window controls can change during capture.
private func artworkSample(_ name: String, in directory: URL) throws -> (pixels: Data, width: Int) {
    let png = try Data(contentsOf: directory.appending(path: name + ".png"))
    guard let bitmap = NSBitmapImageRep(data: png),
          let image = bitmap.cgImage else { throw CocoaError(.fileReadCorruptFile) }
    let crop = CGRect(x: image.width / 2 - 300, y: image.height / 2 - 180, width: 600, height: 400)
    guard let center = image.cropping(to: crop), let buffer = CGContext(data: nil,
        width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 2400,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
        let data = buffer.data else { throw CocoaError(.coderInvalidValue) }
    buffer.draw(center, in: CGRect(origin: .zero, size: crop.size))
    let pixels = Data(bytes: data, count: 400 * 2400)
    var left = 600, right = -1
    // Measure the pan and handle above the localized caption.
    for row in 0..<260 {
        let start = row * 2400
        for x in 0..<600 {
            let pixel = start + 4 * x
            if (0..<3).contains(where: { abs(Int(pixels[pixel + $0]) - Int(pixels[start + $0])) > 15 }) {
                left = min(left, x)
                right = max(right, x)
            }
        }
    }
    return (pixels, max(0, right - left + 1))
}

private func verifyCaptures(in directory: URL) throws {
    func sample(_ name: String) throws -> (pixels: Data, width: Int) { try artworkSample(name, in: directory) }
    let still = try sample("reduced")
    let idle = try sample("overview")
    guard (376...388).contains(idle.width), abs(still.width - idle.width) <= 4,
          try sample("reduced-later").pixels == still.pixels,
          try sample("loading").width >= 376,
          try sample("light").pixels != sample("resumed").pixels else {
        throw NSError(domain: "LoadingReplay", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "Skillet size or motion check failed (loading \(still.width) px, Overview \(idle.width) px)"])
    }
    try Data("Loading \(still.width) px, Overview \(idle.width) px at 2×\n".utf8)
        .write(to: directory.appending(path: "result.txt"))
}

private final class RecordingObserver: NSObject, SCRecordingOutputDelegate, Sendable {
    let completion: AsyncThrowingStream<Void, Error>.Continuation
    init(_ completion: AsyncThrowingStream<Void, Error>.Continuation) { self.completion = completion }
    func recordingOutputDidFinishRecording(_ output: SCRecordingOutput) { completion.finish() }
    func recordingOutput(_ output: SCRecordingOutput, didFailWithError error: Error) { completion.finish(throwing: error) }
}
