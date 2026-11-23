import AppKit
import ScreenCaptureKit

private final class RecordingObserver: NSObject, SCRecordingOutputDelegate, Sendable {
    let completion: AsyncThrowingStream<Void, Error>.Continuation
    init(_ completion: AsyncThrowingStream<Void, Error>.Continuation) { self.completion = completion }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { completion.finish() }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        completion.finish(throwing: error)
    }
}

@MainActor func recordComparison(window: NSWindow, state: ComparisonState) async throws {
    window.appearance = NSAppearance(named: .darkAqua)
    try await Task.sleep(for: .milliseconds(800))
    let available = try await SCShareableContent.currentProcess
    guard let target = available.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) })
    else { throw CocoaError(.fileReadUnknown) }
    let filter = SCContentFilter(desktopIndependentWindow: target)
    let config = SCStreamConfiguration()
    config.width = Int(window.frame.width.rounded(.up)) * 2
    config.height = Int(window.frame.height.rounded(.up)) * 2
    config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    let stream = SCStream(filter: filter, configuration: config, delegate: nil)
    let settings = SCRecordingOutputConfiguration()
    settings.outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("preview.mp4")
    settings.videoCodecType = .h264
    settings.outputFileType = .mp4
    let (finished, completion) = AsyncThrowingStream<Void, Error>.makeStream()
    let observer = RecordingObserver(completion)
    let output = SCRecordingOutput(configuration: settings, delegate: observer)
    try stream.addRecordingOutput(output)
    try await stream.startCapture()
    try await Task.sleep(for: .seconds(4))
    state.running = false
    try await Task.sleep(for: .seconds(2))
    window.appearance = NSAppearance(named: .aqua)
    state.running = true
    try await Task.sleep(for: .seconds(4))
    state.harness = .claude
    state.group = .dots
    try await Task.sleep(for: .seconds(3))
    try await stream.stopCapture()
    for try await _ in finished {}
}
