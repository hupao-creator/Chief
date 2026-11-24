import AppKit
import CoreMedia
import QuartzCore
import ScreenCaptureKit
import SwiftUI
@testable import ChiefUI

private struct HoverFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

@MainActor private final class HoverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private struct HoverFrame {
    let time: Double
    let pixels: Data
}

// Preserve every complete compositor frame. Decoding and PNG export happen after
// capture so writing a failure receipt cannot interrupt the hover that caused it.
private final class HoverStream: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "chief.replay.rail-hover")
    let roi: CGRect
    private(set) var frames: [HoverFrame] = []

    init(roi: CGRect) { self.roi = roi }
    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let buffer = sample.imageBuffer,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]])?.first,
              info[.status] as? Int == SCFrameStatus.complete.rawValue,
              let stamp = info[.displayTime] as? NSNumber else { return }
        let x = Int(roi.minX), y = Int(roi.minY), w = Int(roi.width), h = Int(roi.height)
        guard x >= 0, y >= 0, x + w <= CVPixelBufferGetWidth(buffer), y + h <= CVPixelBufferGetHeight(buffer) else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let address = CVPixelBufferGetBaseAddress(buffer) else { return }
        let pitch = CVPixelBufferGetBytesPerRow(buffer)
        var bytes = Data(count: w * h * 4)
        bytes.withUnsafeMutableBytes { destination in
            for row in 0..<h {
                memcpy(destination.baseAddress! + row * w * 4, address + (y + row) * pitch + x * 4, w * 4)
            }
        }
        var units = mach_timebase_info_data_t()
        mach_timebase_info(&units)
        let time = stamp.doubleValue * Double(units.numer) / Double(units.denom) / 1e9
        frames.append(HoverFrame(time: time, pixels: bytes))
    }
}

private struct RowInk {
    let redX: Double
    let glassRight: Double
    let lowerGlassRight: Double
}

// Read the badge in its own upper strip and the native glass at its midline.
// The distant gray backdrop is sampled on each scanline of the same frame.
private func rowInk(_ frame: HoverFrame, roi: CGRect, centerY: CGFloat, leading: CGFloat,
                    cap: CGFloat, scale: CGFloat) throws -> RowInk {
    let w = Int(roi.width)
    let center = Int(centerY * scale - roi.minY)
    let from = max(0, Int(leading * scale - roi.minX))
    let through = min(w - 4, Int((leading + cap + 7) * scale - roi.minX))
    let result: RowInk? = frame.pixels.withUnsafeBytes { raw in
        let bytes = raw.bindMemory(to: UInt8.self)
        var redMin = w, redMax = -1
        for y in (center - Int(26 * scale))...(center - Int(10 * scale)) {
            for x in from...through {
                let i = 4 * (y * w + x)
                let b = Int(bytes[i]), g = Int(bytes[i + 1]), r = Int(bytes[i + 2])
                if r > 140 && r - g > 65 && r - b > 50 {
                    redMin = min(redMin, x)
                    redMax = max(redMax, x)
                }
            }
        }
        // Read the midline and a second chord through the lower half of the
        // actual capsule. Both edges must travel with the upper unread badge,
        // including on selected glass tinted by a neutral or colorful emoji.
        func edge(at midline: Int) -> Int? {
            var rightmost = -1
            for y in (midline - 2)...(midline + 2) {
                let bg = 4 * (y * w + w - 2)
                for x in from...through {
                    let i = 4 * (y * w + x)
                    let contrast = max(abs(Int(bytes[i]) - Int(bytes[bg])),
                                       abs(Int(bytes[i + 1]) - Int(bytes[bg + 1])),
                                       abs(Int(bytes[i + 2]) - Int(bytes[bg + 2])))
                    if contrast >= 16 { rightmost = max(rightmost, x) }
                }
            }
            return rightmost >= 0 ? rightmost : nil
        }
        guard redMin <= redMax, let middle = edge(at: center),
              let lower = edge(at: center + Int(10 * scale)) else { return nil }
        func point(_ x: Int) -> Double { (Double(x) + roi.minX) / scale }
        return RowInk(redX: (point(redMin) + point(redMax)) / 2, glassRight: point(middle),
                      lowerGlassRight: point(lower))
    }
    guard let result else { throw HoverFailure("Missing badge or glass pixels at row y=\(centerY)") }
    return result
}

@MainActor func replayRailHover(in original: NSWindow, evidence: URL) async throws {
    let size = CGSize(width: 512, height: 330)
    let window = HoverWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
                             backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.hasShadow = false
    window.acceptsMouseMovedEvents = true
    window.setFrameOrigin(CGPoint(x: original.frame.midX - size.width / 2, y: original.frame.midY - size.height / 2))
    let originalCursor = CGEvent(source: nil)?.location
    defer {
        window.close()
        original.makeKeyAndOrderFront(nil)
        if let originalCursor { CGWarpMouseCursorPosition(originalCursor) }
    }
    let cap: CGFloat = 172
    let labels = ["界面问题", "代码审查", "需要截断的很长的界面设计评审与代码审查"]
    let icons = ["🎨", "🔍", "🧰"], counts = [5, 2, 1]
    let children = labels.indices.map { index in
        var filter = NativeOverviewFilter(tag: labels[index], emoji: icons[index], scope: "/hover", count: 6)
        filter.unreadCount = counts[index]
        return filter
    }
    let parent = NativeOverviewFilter(tag: "Workspace", scope: "/hover", count: 12, isDirectory: true, children: children)
    var measured = [String: CGRect]()
    // Bind the production initializer so the same collector also links to the
    // reference revision, whose width argument had a different external label.
    let makeRail = NativeOverviewTagRail.init
    let rail = makeRail(parent, children[1].id, cap, .init(), { _ in }, nil)
    let root = ZStack(alignment: .leading) {
        Color(white: 0.45)
        rail.padding(.leading, 20)
    }.environment(\.colorScheme, .light)
        .environment(\._accessibilityReduceMotion, false)
        .overlayPreferenceValue(OverviewTagBounds.self) { anchors in
            GeometryReader { proxy in
                Color.clear.onChange(of: anchors.mapValues { proxy[$0] }, initial: true) { _, value in measured = value }
            }.allowsHitTesting(false)
        }
    let host = NSHostingView(rootView: root)
    host.sizingOptions = []
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    func move(to point: CGPoint) throws {
        let p = CGPoint(x: point.x, y: size.height - point.y)
        guard let screen = NSScreen.screens.first, let event = NSEvent.mouseEvent(with: .mouseMoved,
            location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)
        else { throw HoverFailure("Cannot create motion") }
        let s = window.convertPoint(toScreen: p)
        guard CGWarpMouseCursorPosition(CGPoint(x: s.x, y: screen.frame.maxY - s.y)) == .success
        else { throw HoverFailure("Could not position the pointer") }
        window.sendEvent(event)
    }
    let away = CGPoint(x: size.width - 15, y: 20)
    try move(to: away)
    try await Task.sleep(for: .milliseconds(400))
    let initial = try children.map { child in
        guard let frame = measured[child.id], abs(frame.width - 42) <= 1 else { throw HoverFailure("Missing compact \(child.tag): \(measured)") }
        return frame
    }
    let scale: CGFloat = 2
    guard let target = try await SCShareableContent.currentProcess.windows.first(where: { $0.windowID == window.windowNumber })
    else { throw HoverFailure("Missing replay window") }
    let cfg = SCStreamConfiguration()
    cfg.width = Int(size.width * scale); cfg.height = Int(size.height * scale)
    cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    cfg.pixelFormat = kCVPixelFormatType_32BGRA
    cfg.showsCursor = false; cfg.ignoreShadowsSingleWindow = true; cfg.ignoreGlobalClipSingleWindow = true
    cfg.queueDepth = 8
    let roi = CGRect(x: (initial[0].minX - 4) * scale, y: (initial[0].minY - 8) * scale,
                     width: (cap + 24) * scale, height: (initial.last!.maxY - initial[0].minY + 16) * scale).integral
    let capture = HoverStream(roi: roi)
    let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: target), configuration: cfg, delegate: nil)
    try stream.addStreamOutput(capture, type: .screen, sampleHandlerQueue: capture.queue)
    try await stream.startCapture()
    var events = [(name: String, time: Double)](), widths = [CGFloat]()
    do {
        try await Task.sleep(for: .milliseconds(250))
        for (name, index, dwell) in [("review", 1, 700), ("ui", 0, 700), ("long", 2, 700),
                                     ("reverse-review", 1, 75), ("reverse-ui", 0, 75), ("reverse-away", -1, 700)] {
            events.append((name, CACurrentMediaTime()))
            try move(to: index < 0 ? away : CGPoint(x: initial[index].minX + 21, y: initial[index].midY))
            try await Task.sleep(for: .milliseconds(dwell))
            if dwell == 700 && index >= 0 { widths.append(measured[children[index].id]?.width ?? 0) }
        }
        try await stream.stopCapture()
    } catch {
        try? await stream.stopCapture()
        throw error
    }
    let frames = capture.queue.sync { capture.frames }
    guard frames.count > 5 else { throw HoverFailure("Too few complete WindowServer frames: \(frames.count)") }
    try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
    var samples = [[String: Any]](), failures = [String](), initialInk = [RowInk]()
    var intermediate = [Set<Int>](repeating: [], count: 3), maxDrift = [Double](repeating: 0, count: 3)
    var trackingPhase = "", lastLeadingRowEdge: Double?
    var monotoneReversal = [String: Double]()
    var openingSamples = [String: [(time: Double, edge: Double)]]()
    let openingRow = ["review": 1, "ui": 0, "long": 2]
    let w = Int(roi.width), h = Int(roi.height)
    let framesDirectory = evidence.appendingPathComponent("rail-hover-frames", isDirectory: true)
    try FileManager.default.createDirectory(at: framesDirectory, withIntermediateDirectories: true)
    for (number, frame) in frames.enumerated() {
        let url = framesDirectory.appendingPathComponent(String(format: "%03d.png", number))
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little)
        guard let provider = CGDataProvider(data: frame.pixels as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw HoverFailure("Could not preserve frame \(number)")
        }
        try png.write(to: url)
        let phase = events.last { $0.time <= frame.time }?.name ?? "compact"
        if trackingPhase != phase {
            trackingPhase = phase
            lastLeadingRowEdge = nil
        }
        var rows = [[String: Any]]()
        for i in labels.indices {
            do {
                let ink = try rowInk(frame, roi: roi, centerY: initial[i].midY,
                                     leading: initial[i].minX, cap: cap, scale: scale)
                if openingRow[phase] == i {
                    openingSamples[phase, default: []].append((frame.time, ink.glassRight))
                    if let previous = lastLeadingRowEdge {
                        monotoneReversal[phase] = max(monotoneReversal[phase] ?? 0, previous - ink.glassRight)
                    }
                    lastLeadingRowEdge = ink.glassRight
                }
                if number == 0 { initialInk.append(ink) }
                if initialInk.count > i {
                    let start = initialInk[i], delta = ink.glassRight - start.glassRight
                    let drift = max(abs((ink.redX - start.redX) - delta),
                                    abs((ink.lowerGlassRight - start.lowerGlassRight) - delta))
                    maxDrift[i] = max(maxDrift[i], drift)
                    if delta > 4 && delta < (i == 2 ? Double(cap) : 95) - 48 { intermediate[i].insert(Int(delta.rounded())) }
                }
                rows.append(["tag": labels[i], "redCenter": ink.redX, "glassRight": ink.glassRight,
                             "lowerGlassRight": ink.lowerGlassRight])
            } catch { failures.append("Frame \(number): \(error)") }
        }
        samples.append(["frame": number, "time": frame.time, "phase": phase, "rows": rows])
    }
    for i in labels.indices {
        if maxDrift[i] > 3 { failures.append("\(labels[i]): corner drift \(maxDrift[i]) pt") }
        if intermediate[i].count < 2 { failures.append("\(labels[i]): missing intermediate widths") }
    }
    for (phase, reversal) in monotoneReversal where reversal > 2 {
        failures.append("Uninterrupted opening reversed during \(phase) by \(reversal) pt")
    }
    // Chinese glyphs resolve through the system's CJK fallback. Allow two points
    // for font metric and backing-pixel rounding in the mounted SwiftUI title.
    let font = NSFont.systemFont(ofSize: OverviewTagMetrics.chipFont, weight: .semibold)
    let fitted = [labels[1], labels[0]].map {
        42 + ceil(($0 as NSString).size(withAttributes: [.font: font]).width) + 12
    } + [cap]
    if widths.count != 3 || zip(widths, fitted).contains(where: { abs($0 - $1) > 2 }) {
        failures.append("Unexpected fitted widths (review, ui, long): \(widths)")
    }
    // Use the first and last *observed* moving frames of each uninterrupted
    // opening. This is a lower bound, independent of startup latency and refresh
    // rate. At least one opening should span substantially more than the old 150ms.
    var observedMotion = [String: Double]()
    for (phase, row) in openingRow where row < initialInk.count {
        guard let timeline = openingSamples[phase], let settled = timeline.last else { continue }
        let moving = timeline.filter { $0.edge > initialInk[row].glassRight + 0.5 && $0.edge < settled.edge - 0.5 }
        if let first = moving.first, let last = moving.last { observedMotion[phase] = last.time - first.time }
    }
    if (observedMotion.values.max() ?? 0) < 0.20 {
        failures.append("No opening has 200ms of observed intermediate motion: \(observedMotion)")
    }
    let receipt: [String: Any] = ["observedIntermediateSeconds": observedMotion,"frames": samples, "fittedWidths": widths, "maximumDriftPoints": maxDrift,
        "expectedFittedWidths": fitted, "openingReversals": monotoneReversal,
        "events": events.map { ["name": $0.name, "time": $0.time] as [String: Any] }, "failures": failures,
        "status": failures.isEmpty ? "passed" : "failed", "scale": scale, "crop": NSStringFromRect(roi)]
    try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
        .write(to: evidence.appendingPathComponent("rail-hover.json"))
    guard failures.isEmpty else { throw HoverFailure(failures.joined(separator: "\n")) }
}
