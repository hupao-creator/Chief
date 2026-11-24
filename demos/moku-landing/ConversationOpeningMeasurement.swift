import AppKit
import QuartzCore
import ScreenCaptureKit
import Vision

private struct OpeningMeasurementError: Error {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}

private struct OpeningFrame {
    let time: Double
    let green: [UInt8]
}

// Read just the bottom of the window, which contains the moving Bar and the
// last line of the reply. Keep OCR, file I/O and comparisons off the input path.
private final class OpeningFrames: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "chief.replay.conversation-frames")
    let width = 720, height = 200
    var frames = [OpeningFrame]()

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let pixels = sample.imageBuffer,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]])?.first,
              info[.status] as? Int == SCFrameStatus.complete.rawValue,
              let stamp = info[.displayTime] as? NSNumber else { return }
        let x = (CVPixelBufferGetWidth(pixels) - width) / 2, y = CVPixelBufferGetHeight(pixels) - height
        guard x >= 0, y >= 0 else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self) else { return }
        let pitch = CVPixelBufferGetBytesPerRow(pixels)
        var green = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let start = (y + row) * pitch + x * 4 + 1
            for column in 0..<width { green[row * width + column] = base[start + column * 4] }
        }
        var units = mach_timebase_info_data_t()
        mach_timebase_info(&units)
        frames.append(.init(time: stamp.doubleValue * Double(units.numer) / Double(units.denom) / 1e9, green: green))
    }

    func analyze(input: Double, ticks: [Double], ending: String, output: URL) throws {
        guard let idle = frames.last(where: { $0.time < input }), let settled = frames.last,
              let provider = CGDataProvider(data: Data(settled.green) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent) else { throw OpeningMeasurementError("Missing reference frames") }
        let request = VNRecognizeTextRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let line = request.results?.first(where: { $0.topCandidates(1).first?.string == ending }) else {
            throw OpeningMeasurementError("Final reply line missing from captured window")
        }
        let box = VNImageRectForNormalizedRect(line.boundingBox, width, height)
        let linePixels = (Int(floor(CGFloat(height) - box.maxY))..<Int(ceil(CGFloat(height) - box.minY))).flatMap { y in
            (Int(floor(box.minX))..<Int(ceil(box.maxX))).map { x in y * width + x }
        }
        func textMatch(_ frame: OpeningFrame) -> Double {
            var intersection = 0, union = 0
            for i in linePixels {
                let visible = frame.green[i] > 160, reference = settled.green[i] > 160
                if visible && reference { intersection += 1 }
                if visible || reference { union += 1 }
            }
            return Double(intersection) / Double(max(1, union))
        }
        func changed(_ frame: OpeningFrame, from previous: OpeningFrame) -> Bool {
            var count = 0
            for y in stride(from: 0, to: height, by: 2) {
                for x in stride(from: 0, to: width, by: 2) {
                    // Ignore the resting character's blink.
                    if abs(x - width / 2) < 34 && y > height - 90 { continue }
                    let i = y * width + x
                    if abs(Int(frame.green[i]) - Int(previous.green[i])) > 12 { count += 1 }
                    if count >= 60 { return true }
                }
            }
            return false
        }
        guard frames.filter({ $0.time < input }).allSatisfy({ !changed($0, from: idle) }),
              textMatch(idle) < 0.1 else { throw OpeningMeasurementError("Idle window failed optical control") }
        var previous = idle, response: Double?, readable: Double?, longestHold = 0.0
        var samples = [[String: Any]]()
        for frame in frames where frame.time >= input {
            let advanced = changed(frame, from: previous), match = textMatch(frame)
            if advanced {
                if response != nil, readable == nil { longestHold = max(longestHold, frame.time - previous.time) }
                if response == nil { response = frame.time }
                previous = frame
            }
            if readable == nil, match >= 0.9 { readable = frame.time }
            samples.append(["ms": (frame.time - input) * 1000, "changed": advanced, "lastLineMatch": match])
        }
        guard let response, let readable, readable >= response else { throw OpeningMeasurementError("Missing visible opening") }
        let gaps = zip(ticks, ticks.dropFirst()).filter { $0.0 < readable && $0.1 >= input }.map { ($0.1 - $0.0) * 1000 }
        guard let mainGap = gaps.max() else { throw OpeningMeasurementError("Missing main run-loop samples") }
        try JSONSerialization.data(withJSONObject: ["responseMS": (response - input) * 1000,
            "readableMS": (readable - input) * 1000, "longestVisualHoldMS": longestHold * 1000,
            "longestMainTickMS": mainGap, "mainTickGapsMS": gaps, "frames": samples], options: [.sortedKeys])
            .write(to: output)
    }
}

@MainActor func measureConversationOpening(window: NSWindow, directory: URL, visit: Int, ending: String,
                                           open: () async throws -> Void) async throws {
    guard let target = try await SCShareableContent.currentProcess.windows.first(where: { $0.windowID == window.windowNumber })
    else { throw OpeningMeasurementError("Missing replay window") }
    let config = SCStreamConfiguration()
    config.width = Int(window.frame.width)
    config.height = Int(window.frame.height)
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    config.ignoreGlobalClipSingleWindow = true
    let capture = OpeningFrames()
    let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: target), configuration: config, delegate: nil)
    try stream.addStreamOutput(capture, type: .screen, sampleHandlerQueue: capture.queue)
    try await stream.startCapture()
    var ticks = [Double]()
    let heartbeat = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in
        MainActor.assumeIsolated { ticks.append(CACurrentMediaTime()) }
    }
    RunLoop.main.add(heartbeat, forMode: .common)
    defer { heartbeat.invalidate() }
    let input: Double
    do {
        try await Task.sleep(for: .milliseconds(250))
        if visit == 1, CommandLine.arguments.contains("--profile-opening") {
            let sample = Process()
            sample.executableURL = URL(filePath: "/usr/bin/sample")
            sample.arguments = [String(ProcessInfo.processInfo.processIdentifier), "1", "1", "-file",
                                directory.appending(path: "opening.sample.txt").path]
            try sample.run()
            // Attach before the input. Profiled visits are diagnostic runs.
            try await Task.sleep(for: .milliseconds(100))
        }
        input = CACurrentMediaTime()
        try await open()
        try await Task.sleep(for: .milliseconds(800))
        try await stream.stopCapture()
    } catch {
        try? await stream.stopCapture()
        throw error
    }
    try capture.queue.sync {
        try capture.analyze(input: input, ticks: ticks, ending: ending, output: directory.appending(path: "opening-\(visit).json"))
    }
}
