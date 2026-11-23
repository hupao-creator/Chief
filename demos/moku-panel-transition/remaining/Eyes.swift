import AppKit
import QuartzCore
import ScreenCaptureKit
@testable import ChiefUI

// The flat black lanes contain only the original CAShapeLayers. Collect the
// same sRGB bytes for the reference/reference and reference/product pair.
func rgba(_ image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { raw in
        let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
}

final class LaneStream: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "chief.bar.eye-pixels")
    var frames = [[Double]]()
    let region: CGRect
    init(region: CGRect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)) { self.region = region }
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        let received = CACurrentMediaTime()
        guard let info = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]])?.first,
            info[.status] as? Int == SCFrameStatus.complete.rawValue, let stamp = info[.displayTime] as? NSNumber,
            let pixels = buffer.imageBuffer else { return }
        var units = mach_timebase_info_data_t()
        mach_timebase_info(&units)
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let bytes = CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self) else { return }
        let pitch = CVPixelBufferGetBytesPerRow(pixels), width = CVPixelBufferGetWidth(pixels) / 3
        let height = CVPixelBufferGetHeight(pixels)
        var row = [stamp.doubleValue * Double(units.numer) / Double(units.denom) / 1e9, received]
        for lane in 0..<3 {
            var ink = 0
            for y in Int(Double(height) * region.minY)..<Int(Double(height) * region.maxY) {
                for x in Int(Double(width) * region.minX)..<Int(Double(width) * region.maxX) {
                    ink += Int(bytes[y * pitch + (width * lane + x) * 4 + 1])
                }
            }
            row.append(Double(ink))
        }
        frames.append(row)
    }
}

@MainActor func betweenBlinks() async throws {
    while NativeMokuCapsuleBlinkTiming.window(at: .now).lowerBound.timeIntervalSinceNow < 1.1 {
        try await pause(35)
    }
}

@MainActor func eyeVisit() async throws {
    let panel = try Panel(size: .init(width: 240, height: 70))
    defer { panel.close() }
    let root = panel.contentView!
    root.layer?.backgroundColor = NSColor.black.cgColor
    let references = [ReferenceCharacterMotion(), ReferenceCharacterMotion(), ReferenceCharacterMotion()]
    let product = NativeMokuCharacterMotion()
    let views: [NSView] = references.prefix(2).map { ReferenceCharacterCanvas(controller: $0, seat: .face) }
        + [NativeMokuCharacterCanvas(controller: product, seat: .face)]
    for (index, view) in views.enumerated() {
        view.frame = CGRect(x: 80 * index + 11, y: 10, width: 58, height: 50)
        root.addSubview(view)
    }
    let eyes = views.map { $0.layer!.sublayers!.compactMap { $0 as? CAShapeLayer } }
    try check(eyes.allSatisfy { $0.count == 2 }, "Two resident layers per face")
    // Render an independently compiled original at the very same device
    // pixels. The opaque black control seat covers the product without
    // hiding its NSView or interrupting its installed animation.
    let cover = NSView(frame: CGRect(x: 160, y: 0, width: 80, height: 70))
    cover.wantsLayer = true
    cover.layer?.backgroundColor = NSColor.black.cgColor
    let controlFace = ReferenceCharacterCanvas(controller: references[2], seat: .face)
    controlFace.frame = CGRect(x: 11, y: 10, width: 58, height: 50)
    cover.addSubview(controlFace)
    root.addSubview(cover)
    func showControl(_ visible: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cover.layer?.opacity = visible ? 1 : 0
        CATransaction.commit()
        CATransaction.flush()
    }
    showControl(false)
    func input(_ expression: MokuExpression) -> NativeMokuCharacterInput {
        NativeMokuCharacterInput(expression: expression, focus: 0, running: false,
            presentsReasoning: false, capsuleSize: NativeMokuCapsuleLayout.idleSize, cornerRadius: 29, motion: true, dark: true)
    }
    func configure(_ expression: MokuExpression) {
        references.forEach { $0.configure(input(expression)) }
        product.configure(input(expression))
    }
    configure(.idle)
    let filter = try await panel.filter(), config = panel.configuration()
    let streamOutput = LaneStream()
    let stream = SCStream(filter: filter, configuration: config, delegate: nil)
    try stream.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: streamOutput.queue)
    try await stream.startCapture()
    var heldFrames = [[String: Any]]()
    func hold(_ name: String) async throws {
        try await pause(45)
        let start = CACurrentMediaTime()
        usleep(200_000)
        let end = CACurrentMediaTime()
        try await pause(75)
        let rows = streamOutput.queue.sync { streamOutput.frames.filter { $0[0] >= start && $0[1] <= end } }
        heldFrames.append(["visit": name, "start": start, "end": end, "frames": rows,
                           "columns": ["displaySeconds", "receivedSeconds", "reference1", "reference2", "product"]])
    }
    try await pause(300)
    try await betweenBlinks()
    configure(.happy)
    try await hold("unread")
    configure(.idle)
    try await hold("read-during-reveal")
    try await pause(500)
    try await betweenBlinks()
    configure(.curious)
    try await hold("permission")
    try await stream.stopCapture()
    try save(heldFrames, "eye-holds.json")
    for hold in heldFrames {
        let rows = hold["frames"] as! [[Double]]
        let productValues = rows.map { $0[4] }
        let increasing = hold["visit"] as? String != "read-during-reveal"
        try check(rows.count >= 3 && Set(productValues).count >= 3 &&
                  Set(rows.map { $0[2] }).count <= 2 &&
                  Set(rows.map { $0[3] }).count <= 2 &&
                  (increasing ? productValues.last! > productValues.first! : productValues.last! < productValues.first!),
                  "No independently displayed expression for " + String(describing: hold["visit"]))
    }

    var samples = [[String: Any]]()
    for (name, expression) in [("clear-permission", MokuExpression.idle), ("unread", .happy),
                               ("replace-with-permission", .curious), ("restore-unread", .happy), ("read", .idle),
                               ("interrupt-unread-with-read", .idle)] {
        try await pause(500)
        try await betweenBlinks()
        var redirectPhase: Double?
        if name == "interrupt-unread-with-read" {
            // Use only the submitted leg's clock anchor to synchronize the
            // independent old controller. It calculates its own geometry
            // and velocity before turning toward the new expression.
            func anchor() throws -> Double {
                guard let value = Mirror(reflecting: product).descendant("frameClock") as? Double else {
                    throw ReplayFailure("Unavailable product clock anchor")
                }
                return value
            }
            configure(.happy)
            let first = try anchor()
            try await pause(137)
            product.configure(input(expression))
            let elapsed = try anchor() - first
            try check((100..<320).contains(elapsed), "Redirect happened outside the moving interval")
            redirectPhase = elapsed
            references.forEach { $0.seek(milliseconds: elapsed); $0.configure(input(expression)) }
        } else { configure(expression) }
        let tracks = try eyes[2].map { layer -> CAAnimation in
            guard let track = layer.animation(forKey: "moku.expression") else { throw ReplayFailure("Missing " + name + " track") }
            return track
        }
        var worst = -1
        let phases = Array(stride(from: 0.0, through: 420, by: 10)) + [2.5, 7.25, 73.25, 123.75, 239.5, 368.75, 418.75]
        for ms in phases.sorted() {
            references.forEach { $0.seek(milliseconds: ms) }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for row in eyes { for eye in row { eye.removeAnimation(forKey: "moku.blink") } }
            controlFace.layer?.sublayers?.forEach { $0.removeAnimation(forKey: "moku.blink") }
            for (eye, track) in zip(eyes[2], tracks) {
                // Core Animation freezes the installed animation. Seek a
                // mutable copy of those exact keyframes in the fixture.
                let sought = track.copy() as! CAAnimation
                sought.speed = 0
                sought.timeOffset = Double(ms) / 1000
                sought.beginTime = 0
                if ms == 420 { eye.removeAnimation(forKey: "moku.expression") }
                else { eye.add(sought, forKey: "moku.expression") }
            }
            CATransaction.commit()
            CATransaction.flush()
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let bytes = rgba(image)
            showControl(true)
            let originalImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let original = rgba(originalImage)
            showControl(false)
            let lane = image.width / 3
            var peak = 0, control = 0, sameSlot = 0, differing = 0
            for y in 0..<image.height {
                for x in lane / 5 ..< lane * 4 / 5 {
                    let i = (y * image.width + x) * 4
                    var delta = 0
                    for channel in 0..<3 {
                        let j = i + channel
                        let a = Int(bytes[j]), b = Int(bytes[j + lane * 4]), c = Int(bytes[j + lane * 8])
                        control = max(control, abs(a - b))
                        peak = max(peak, abs(b - c))
                        delta = max(delta, abs(c - Int(original[j + lane * 8])))
                    }
                    sameSlot = max(sameSlot, delta)
                    if delta != 0 { differing += 1 }
                }
            }
            var row: [String: Any] = ["leg": name, "ms": ms, "controlPeak": control, "adjacentPeak": peak,
                                      "sameSlotPeak": sameSlot, "pixels": differing]
            if let redirectPhase { row["redirectAtMS"] = redirectPhase }
            samples.append(row)
            if ms == 210 {
                try savePNG(image, "half-" + name + ".png")
                try savePNG(originalImage, "control-half-" + name + ".png")
            }
            if sameSlot > worst {
                worst = sameSlot
                try savePNG(image, "eyes-" + name + ".png")
            }
        }
    }
    try save(samples, "eye-phases.json")
    // Exercise real visibility and blinking after the optical comparison.
    try await betweenBlinks()
    configure(.curious)
    try await pause(95)
    views[2].isHidden = true
    let hiddenClock = product.clock
    try await pause(155)
    let pausedClock = product.clock
    try check(pausedClock == hiddenClock && eyes[2].allSatisfy { $0.animation(forKey: "moku.expression") == nil },
              "Hiding the face must withdraw its track and freeze the logical pose")
    views[2].isHidden = false
    try await until("Resumed face settled") { !product.isTransitioning }
    try await betweenBlinks()
    configure(.idle)
    try await pause(115)
    configure(.happy)
    let redirectedOnLink = product.hasScheduledFrame && eyes[2].allSatisfy { $0.animation(forKey: "moku.expression") == nil }
    try await until("Redirected mixed expression settled") { !product.isTransitioning }
    while !(0.12...0.32).contains(NativeMokuCapsuleBlinkTiming.window(at: .now).lowerBound.timeIntervalSinceNow) {
        try await pause(15)
    }
    configure(.idle)
    let retainedBlink = eyes[2].allSatisfy { $0.animation(forKey: "moku.blink") != nil && $0.animation(forKey: "moku.expression") == nil }
    let sharedFrames = product.hasScheduledFrame
    try await until("Blink-overlap expression settled") { !product.isTransitioning }
    try save(["hiddenClock": hiddenClock, "pausedClock": pausedClock, "overlapKeptBlink": retainedBlink,
              "overlapUsedDisplayLink": sharedFrames, "thirdExpressionUsedDisplayLink": redirectedOnLink,
              "settled": !product.isTransitioning], "eye-lifecycle.json")
    try check(retainedBlink && sharedFrames && redirectedOnLink, "Blink overlap and mixed redirects must share their display clock")
    try check(samples.allSatisfy { ($0["sameSlotPeak"] as! Int) == 0 }, "Same-position eye phase raster mismatch")
}
