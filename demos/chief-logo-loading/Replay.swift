import AppKit
import ScreenCaptureKit
import SwiftUI
import ChiefCore
import ChiefPluginAPI
@testable import ChiefUI

@main @MainActor private struct LoadingReplay: App {
    let model: NativeWorkspaceModel
    @State private var reduced = false
    @State private var light = false

    init() {
        do {
            try prepareIsolatedNativeReplay()
            let directory = URL(filePath: FileManager.default.currentDirectoryPath)
            model = try NativeWorkspaceModel(client: RuntimeClient(profile: RuntimeProfile(dataDirectory: directory)),
                preferences: DesktopPreferences(directory: directory),
                plugins: .init(harnesses: [], sidecards: [], applications: []), locale: .chinese)
        } catch { fatalError(String(describing: error)) }
    }

    var body: some Scene {
        Window("Chief", id: "loading-replay") {
            NativeRuntimeSurface(model: model, showsConnectionNotice: false) {
                NativeOverviewStatusEmptyState(title: "没有运行中的会话")
            }
            .background(light ? Color(white: 0.94) : Color(white: 0.15))
            .preferredColorScheme(light ? .light : .dark)
            .environment(\._accessibilityReduceMotion, reduced)
            .task {
                do { try await replay(); exit(0) }
                catch { print(error); exit(1) }
            }
        }
        .defaultSize(width: 900, height: 560)
        .restorationBehavior(.disabled)
    }

    private func replay() async throws {
        try await Task.sleep(for: .milliseconds(500))
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "loading-replay" }) else {
            throw CocoaError(.coderValueNotFound)
        }
        window.setContentSize(NSSize(width: 900, height: 560))
        window.orderFrontRegardless()
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
        try await Task.sleep(for: .milliseconds(350))

        let chief = try HarnessThread(id: "moku", harnessID: "codex", revision: 0, sessionState: .null,
            observation: .init(), cwd: "/fixture", settings: .object([:]), createdAt: 1, updatedAt: 2,
            title: "Chief", tags: [], moku: true, transcript: .array([]))
        let snapshot: JSONValue = .object(["revision": .integer(1), "settingsRevision": .integer(0),
            "defaultCwd": .text("/fixture"), "settings": .object([:]), "threads": .array([chief.json]), "executions": .array([]),
            "applicationThreads": .array([])])
        await model.installPrepared(snapshot, event: .snapshot(snapshot, authority: UUID()))
        guard model.hasInitialContent, !model.waitingForInitialCatalog else { throw CocoaError(.coderInvalidValue) }
        try await Task.sleep(for: .milliseconds(300))
        try await capture("overview")
        try await stream.stopCapture()
        for try await _ in done {}
        try verifyCaptures(in: directory)
    }
}

// Compare only the artwork region. Window controls can change during capture.
private func verifyCaptures(in directory: URL) throws {
    func sample(_ name: String) throws -> (pixels: Data, width: Int) {
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
        for row in 0..<400 {
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
