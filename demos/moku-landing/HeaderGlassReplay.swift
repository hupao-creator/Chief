import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision
@testable import ChiefUI

private struct HeaderFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

private struct HeaderGlassFixture: View {
    let textured: Bool
    let filters: [NativeOverviewFilter]
    @State var selected: NativeOverviewFilter?
    let measured: ([String: CGRect]) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: 0)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                    Gradient(colors: [.init(white: 0.47), .init(white: 0.62)]), center: center, startRadius: 0, endRadius: 160))
                if textured {
                    for x in stride(from: 0, to: size.width, by: 6) {
                        context.fill(Path(CGRect(x: x, y: 0, width: 3, height: size.height)), with: .color(Color(white: 0.77)))
                    }
                }
            }
            NativeOverviewChrome(filters: filters, selectedTag: selected?.tag ?? "", selectedScope: selected?.scope ?? "",
                selectedKind: selected.map { $0.isDirectory ? .directory : .semantic }, onTagChange: { selected = $0 })
        }
        .overlayPreferenceValue(OverviewTagBounds.self) { anchors in
            GeometryReader { proxy in
                Color.clear.onChange(of: anchors.mapValues { proxy[$0] }, initial: true) { _, frames in measured(frames) }
            }.allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

@MainActor private func windowImage(_ window: NSWindow) async throws -> CGImage {
    // Inactive windows suppress Liquid Glass tints. Wait for the foreground
    // launch to settle before drawing conclusions from their pixels.
    for _ in 0..<20 {
        if NSApp.isActive && window.isKeyWindow && window.occlusionState.contains(.visible) { break }
        try await Task.sleep(for: .milliseconds(100))
    }
    guard NSApp.isActive && window.isKeyWindow && window.occlusionState.contains(.visible) else {
        throw HeaderFailure("Header capture window unavailable (active: \(NSApp.isActive), key: \(window.isKeyWindow), visible: \(window.occlusionState.contains(.visible)))")
    }
    guard let target = try await SCShareableContent.currentProcess.windows.first(where: { $0.windowID == window.windowNumber }) else {
        throw HeaderFailure("Missing mounted header window")
    }
    let config = SCStreamConfiguration()
    config.width = Int(window.frame.width * 2)
    config.height = Int(window.frame.height * 2)
    config.showsCursor = false
    config.ignoreGlobalClipSingleWindow = true
    config.ignoreShadowsSingleWindow = true
    return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: config)
}

@MainActor func replayHeaderGlass(in window: NSWindow, evidence: URL) async throws {
    let appearance = window.appearance
    let content = window.contentView
    defer {
        window.appearance = appearance
        window.contentView = content
    }
    var chief = NativeOverviewFilter(tag: "Chief", scope: "/Chief", count: 8, isDirectory: true)
    chief.unreadCount = 8
    var blue = NativeOverviewFilter(tag: "Blue", emoji: "🔵", scope: "inbox", count: 4)
    blue.unreadCount = 3
    var observations = [[String: Any]]()
    func save(_ status: String) throws {
        try JSONSerialization.data(withJSONObject: ["status": status, "frames": observations],
            options: [.prettyPrinted, .sortedKeys]).write(to: evidence.appending(path: "header-glass.json"), options: .atomic)
    }
    for (scheme, name) in [(ColorScheme.light, "light"), (.dark, "dark")] {
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        for textured in [false, true] {
            var buttonFrames = [String: CGRect]()
            let host = NSHostingView(rootView: HeaderGlassFixture(textured: textured, filters: [chief, blue], selected: chief, measured: { buttonFrames = $0 })
                .environment(\.colorScheme, scheme))
            host.sizingOptions = []
            window.contentView = host
            try await Task.sleep(for: .milliseconds(680))
            let image = try await windowImage(window)
            let bounds = try [chief.id, blue.id].map { id in
                guard let rect = buttonFrames[id] else { throw HeaderFailure("Missing production header anchor " + id) }
                return rect
            }
            let row = bounds.reduce(CGRect.null) { $0.union($1) }
            let crop = CGRect(x: ((row.midX - 154.5) * 2).rounded(), y: ((row.minY - 9) * 2).rounded(),
                              width: 618, height: 174)
            guard let header = image.cropping(to: crop),
                  let png = NSBitmapImageRep(cgImage: header).representation(using: .png, properties: [:]) else {
                throw HeaderFailure("Cannot crop the production header")
            }
            let step = "header-" + name + (textured ? "-texture" : "")
            try png.write(to: evidence.appending(path: step + ".png"))
            let pixels = NSBitmapImageRep(cgImage: image)
            func color(_ x: CGFloat, _ y: CGFloat) -> NSColor {
                pixels.colorAt(x: Int(x * 2), y: Int(y * 2))!.usingColorSpace(.sRGB)!
            }
            func gray(_ c: NSColor) -> CGFloat { 0.21 * c.redComponent + 0.72 * c.greenComponent + 0.07 * c.blueComponent }
            func modulation(_ y: CGFloat) -> CGFloat {
                let middle = bounds[0].midX
                let levels = (0..<56).map { gray(color(middle - 14 + CGFloat($0) / 2, y)) }.sorted()
                return levels[50] - levels[5]
            }
            let selected = bounds[0]
            // Sample only exposed background just outside the curved capsules.
            // The two pixels straddle the previous rectangular viewport cut.
            func across(_ x: CGFloat, _ y: CGFloat, horizontal: Bool = false) -> CGFloat {
                let dx: CGFloat = horizontal ? 0.25 : 0
                let dy: CGFloat = horizontal ? 0 : 0.25
                return abs(gray(color(x - dx, y - dy)) - gray(color(x + dx, y + dy)))
            }
            let clippingSteps = [across(selected.minX + 0.25, selected.maxY),
                                 across((selected.maxX + bounds[1].minX) / 2, selected.maxY),
                                 across(bounds[1].maxX, bounds[1].midY - 7, horizontal: true)]
            let gaps = [bounds[1].minX - bounds[0].maxX]
            let face = gray(color(selected.midX, selected.maxY - 7))
            let ink = (-8...8).flatMap { row in
                (0..<36).map { column in gray(color(selected.midX + CGFloat(column) / 2, selected.midY + CGFloat(row) / 2)) }
            }.sorted()
            let contrast = max(face - ink[ink.count / 20], ink[ink.count * 95 / 100] - face)
            func badgePixels(_ frame: CGRect) -> Int {
                var red = 0
                for y in Int((frame.minY - 5) * 2)..<Int((frame.minY + 12) * 2) {
                    for x in Int((frame.maxX - 25) * 2)..<Int(frame.maxX * 2) {
                        let c = color(CGFloat(x) / 2, CGFloat(y) / 2)
                        if c.redComponent > 0.7 && c.redComponent - max(c.blueComponent, c.greenComponent) > 0.35 { red += 1 }
                    }
                }
                return red
            }
            let red = badgePixels(selected), semanticBadge = badgePixels(bounds[1])
            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            try VNImageRequestHandler(cgImage: header).perform([request])
            let labels = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let receipt: [String: Any] = ["step": step, "text": labels, "redBadgePixels": red, "semanticBadgePixels": semanticBadge,
                "faceRGB": filterFaceRGB(pixels, at: selected, scale: 2),
                "gapsInPoints": gaps, "shadowBoundaryLumaSteps": clippingSteps, "faceLuma": face, "textLumaDifference": contrast,
                "faceModulation": modulation(selected.minY + 6), "backdropModulation": modulation(selected.minY - 5)]
            observations.append(receipt)
            let text = labels.joined()
            guard red > 80, semanticBadge > 80, contrast > 0.20,
                  bounds.allSatisfy({ abs($0.height - OverviewTagMetrics.railDiameter) <= 0.5 }), !text.contains("全部"), !text.contains("…"),
                  ["Chief", "Blue", "8", "3"].allSatisfy(text.contains),
                  textured || clippingSteps.allSatisfy({ $0 < 0.018 }),
                  !textured || modulation(selected.minY + 6) < modulation(selected.minY - 5) else {
                try save("failed")
                throw HeaderFailure("Header badge or text missing: \(receipt)")
            }
            if !textured {
                let ids = [chief.id, blue.id]
                var images = [pixels]
                for index in [1, 0] {
                    try clickFilter(in: window, at: bounds[index])
                    try await Task.sleep(for: .milliseconds(550))
                    let changed = try await windowImage(window)
                    images.append(NSBitmapImageRep(cgImage: changed))
                    if index == 1, let cropped = changed.cropping(to: crop) {
                        try NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])?
                            .write(to: evidence.appending(path: "inbox-tag-" + name + ".png"))
                    }
                }
                let views = images.map { readFaceColors($0, ids: ids, frames: buttonFrames) }
                let results = try [(0, 0, 1), (1, 1, 2)].map { index, selected, idle in
                    let id = ids[index]
                    var result = try tintResult(id: id, selected: views[selected], idle: views[idle], hue: id == blue.id ? .blue : .gold)
                    if id == blue.id, let face = views[idle][id] {
                        let (count, fraction) = preservedEmoji(selected: images[selected], idle: images[idle], frame: bounds[index], idleFace: face)
                        result["emojiInkPixels"] = count
                        result["emojiAgreement"] = fraction
                        result["passed"] = result["passed"] as? Bool == true && count >= 50 && fraction >= 0.75
                    }
                    return result
                }
                observations.append(["step": "header-tints-" + name, "choices": results])
                if results.contains(where: { $0["passed"] as? Bool != true }) {
                    try save("failed")
                    throw HeaderFailure("Header tint mismatch: \(results)")
                }
            }
        }
        let rows = try await sideTints(in: window, scheme: scheme, name: name, evidence: evidence)
        observations.append(["step": "side-tints-" + name, "choices": rows])
        if rows.contains(where: { $0["passed"] as? Bool != true }) {
            try save("failed")
            throw HeaderFailure("Side tint mismatch: \(rows)")
        }
    }
    try save("passed")
}

private enum TintHue: String { case gold, blue, green, warm, neutral }

private func readFaceColors(_ pixels: NSBitmapImageRep, ids: [String], frames: [String: CGRect]) -> [String: [Double]] {
    Dictionary(uniqueKeysWithValues: ids.compactMap { id in
        frames[id].map { (id, filterFaceRGB(pixels, at: $0, scale: 2)) }
    })
}

private func tintResult(id: String, selected: [String: [Double]], idle: [String: [Double]], hue: TintHue) throws -> [String: Any] {
    guard let face = selected[id], let reference = idle[id] else { throw HeaderFailure("Missing tint sample " + id) }
    let delta = zip(face, reference).map(-)
    let r = delta[0], g = delta[1], b = delta[2]
    let visible = delta.contains { abs($0) > 0.035 }
    let pairedHue: Bool = switch hue {
    case .gold: r - g > 0.015 && g - b > 0.035
    case .blue: b - r > 0.04 && b - g > 0.02 && g > r
    case .green: g - r > 0.025 && g - b > 0.04
    case .warm: r - b > 0.03 && g - b > 0
    case .neutral: max(r, g, b) - min(r, g, b) < 0.065
    }
    return ["id": id, "hue": hue.rawValue, "selected": face, "unselected": reference, "passed": visible && pairedHue]
}

@MainActor private func clickFilter(in window: NSWindow, at rect: CGRect) throws {
    let point = CGPoint(x: rect.minX + rect.height / 2, y: window.frame.height - rect.midY)
    for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
        guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
        else { throw HeaderFailure("Cannot click the measured filter") }
        window.sendEvent(event)
    }
}

private struct SideTintFixture: View {
    let folder: NativeOverviewFilter
    let measured: ([String: CGRect]) -> Void
    @State var tag: String?
    @State var status: NativeOverviewStatusFilter = .all

    var body: some View {
        HStack {
            NativeOverviewTagRail(parent: folder, selectedID: tag, maximumWidth: 145, strings: .init(), onTagChange: { tag = $0?.id })
            Spacer()
            NativeOverviewStatusRail(status: status, maximumWidth: 145, strings: .init(), onStatusChange: { status = $0 })
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.56))
        .overlayPreferenceValue(OverviewTagBounds.self) { anchors in
            GeometryReader { proxy in
                Color.clear.onChange(of: anchors.mapValues { proxy[$0] }, initial: true) { _, frames in measured(frames) }
            }.allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// Compare interior emoji pixels to the same glyph in its unselected control.
// Exclude the glass-colored background and antialiased fringe from the reference.
private func preservedEmoji(selected: NSBitmapImageRep, idle: NSBitmapImageRep,
                            frame: CGRect, idleFace: [Double]) -> (Int, Double) {
    let x = Int((frame.minX + frame.height / 2) * 2), y = Int(frame.midY * 2)
    var ink = 0, matches = 0
    for dy in -18...18 {
        for dx in -18...18 {
            guard let a = selected.colorAt(x: x + dx, y: y + dy)?.usingColorSpace(.sRGB),
                  let b = idle.colorAt(x: x + dx, y: y + dy)?.usingColorSpace(.sRGB) else { continue }
            if max(abs(b.redComponent - idleFace[0]), abs(b.greenComponent - idleFace[1]), abs(b.blueComponent - idleFace[2])) <= 0.23 { continue }
            ink += 1
            if max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent)) < 0.075 {
                matches += 1
            }
        }
    }
    return (ink, Double(matches) / Double(max(1, ink)))
}

@MainActor private func sideTints(in window: NSWindow, scheme: ColorScheme, name: String, evidence: URL) async throws -> [[String: Any]] {
    let blue = NativeOverviewFilter(tag: "Blue", emoji: "🔵", scope: "/Chief", count: 1)
    let apple = NativeOverviewFilter(tag: "Apple", emoji: "🍏", scope: "/Chief", count: 1)
    let orange = NativeOverviewFilter(tag: "Orange", emoji: "🟠", scope: "/Chief", count: 1)
    let folder = NativeOverviewFilter(tag: "Chief", scope: "/Chief", count: 3, isDirectory: true, children: [orange, blue, apple])
    var frames = [String: CGRect]()
    let host = NSHostingView(rootView: SideTintFixture(folder: folder, measured: { frames = $0 }, tag: orange.id)
        .environment(\.colorScheme, scheme))
    host.sizingOptions = []
    window.contentView = host
    let configurations = [[orange.id, "all"], [blue.id, "running"], [apple.id, "completed"]]
    let ids = configurations.flatMap { $0 }
    var samples = [[String: [Double]]](), images = [NSBitmapImageRep]()
    var glyphSeats = [String: CGRect]()
    for (index, pair) in (configurations + [configurations[0]]).enumerated() {
        if index > 0 {
            for id in pair {
                guard let frame = frames[id] else { throw HeaderFailure("Missing side filter " + id) }
                try clickFilter(in: window, at: frame)
            }
        }
        try await Task.sleep(for: .milliseconds(650))
        let image = try await windowImage(window)
        let pixels = NSBitmapImageRep(cgImage: image)
        images.append(pixels)
        if index == 0 {
            // Both rails keep their glyph seats fixed as the labels open inward.
            for (id, frame) in frames {
                let edge: CGRectEdge = id.hasPrefix("semantic:") ? .minXEdge : .maxXEdge
                glyphSeats[id] = frame.divided(atDistance: frame.height, from: edge).slice
            }
        }
        samples.append(readFaceColors(pixels, ids: ids, frames: glyphSeats))
        try pixels.representation(using: .png, properties: [:])?.write(to: evidence.appending(path: "side-tints-\(name)-\(index).png"))
    }
    let hues: [TintHue] = [.warm, .warm, .blue, .warm, .green, .neutral]
    return try ids.enumerated().map { offset, id in
        let index = offset / 2
        let next = index + 1
        var result = try tintResult(id: id, selected: samples[index], idle: samples[next], hue: hues[offset])
        if let frame = glyphSeats[id], let idle = samples[next][id] {
            let (count, fraction) = preservedEmoji(selected: images[index], idle: images[next], frame: frame, idleFace: idle)
            result["emojiInkPixels"] = count
            result["emojiAgreement"] = fraction
            result["passed"] = result["passed"] as? Bool == true && count >= 50 && fraction >= 0.75
        }
        return result
    }
}
