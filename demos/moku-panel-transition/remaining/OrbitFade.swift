import AppKit
@testable import ChiefUI

/// The panel is fully offscreen. Drive both native controllers with the same
/// display-frame deltas so each interrupted frame has an uninterrupted peer.
@MainActor func orbitFadeFrames(panel: Panel, character: NativeMokuCharacterMotion,
                               setRunning: (Bool, String) async throws -> Void) async throws {
    let reference = NativeMokuCharacterMotion()
    let bounds = CGRect(x: 0, y: 0, width: 208, height: 84)
    var rows = [[String: Any]]()
    var previousDots: [MokuRunningFrame.Dot] = []

    func capture(_ event: String, delta: Double, image: Bool) throws {
        guard let input = character.input else { throw ReplayFailure("Missing Dock input") }
        try check(input.capsuleSize == CGSize(width: 168, height: 44) && !character.hasScheduledFrame,
                  "Expected an offscreen compact Dock on the fixture clock")
        let dots = character.orbitDots, alpha = character.orbitOpacity
        let bitmap = CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height),
            bitsPerComponent: 8, bytesPerRow: Int(bounds.width) * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.translateBy(x: 0, y: bounds.height)
        bitmap.scaleBy(x: 1, y: -1)
        character.paintDecorations(in: bitmap, bounds: bounds)
        guard let ink = bitmap.makeImage() else { throw ReplayFailure("Missing orbit pixels") }
        let bytes = rgba(ink)
        let area = stride(from: 3, to: bytes.count, by: 4).reduce(0.0) { $0 + Double(bytes[$1]) / 255 }
        rows.append(["event": event, "ms": character.clock, "opacity": alpha, "inkArea": area,
                     "centers": dots.map { [$0.x, $0.y] }])
        if image {
            try savePNG(ink, event + "-ink.png")
            try panel.saveOffscreenImage(event)
        }
        try check(abs(area - 3 * .pi * 2.5 * 2.5 * alpha) < 2, "Painted dot area: " + event)
        try check(dots.count == (alpha > 0 ? 3 : 0), "Visible dot count: " + event)
        for (index, dot) in dots.enumerated() {
            let peer = reference.orbitDots[index]
            try check(hypot(dot.x - peer.x, dot.y - peer.y) < 0.001, "Orbit phase changed: " + event)
            // Distance from the 124-point centre segment of a 168 × 44 capsule.
            let radius = hypot(max(0, abs(dot.x) - 62), dot.y)
            try check(abs(radius - 27.5) < 0.15, "Dot left the contour: " + event)
            if !previousDots.isEmpty {
                let last = previousDots[index]
                let travel = hypot(dot.x - last.x, dot.y - last.y)
                if delta == 0 { try check(travel < 0.001, "Jump on configuration: " + event) }
                else { try check(travel > 1 && travel < 6, "Stopped or jumped between frames: " + event) }
            }
        }
        previousDots = dots
    }

    func step(_ event: String, frames: Int) throws {
        for frame in 1...frames {
            let prior = character.orbitOpacity
            character.advanceFrame(milliseconds: 25)
            reference.advanceFrame(milliseconds: 25)
            try capture(event, delta: 25, image: frame == frames)
            if character.input?.running == true && prior < 1 {
                try check(character.orbitOpacity > prior, "Fade-in stalled: " + event)
            } else if character.input?.running == false && prior > 0 {
                try check(character.orbitOpacity < prior, "Fade-out stalled: " + event)
            }
        }
        try save(rows, "orbit-frames.json")
    }

    func redirect(_ running: Bool, _ key: String, _ event: String) async throws {
        let prior = character.orbitOpacity
        try await setRunning(running, key)
        try check(character.orbitOpacity == prior, "Opacity jumped on " + event)
        try capture(event, delta: 0, image: false)
    }

    try await setRunning(true, "first")
    guard let first = character.input else { throw ReplayFailure("Missing initial run") }
    reference.configure(first)
    try capture("start", delta: 0, image: true)
    try step("enter-mid", frames: 11)
    try await redirect(false, "first", "interrupt-entry")
    try step("early-exit-mid", frames: 4)
    try await redirect(true, "second", "reverse-before-hidden")
    try step("reverse-mid", frames: 8)
    try step("fully-visible", frames: 16)
    try check(character.orbitOpacity == 1, "Orbit never reached full opacity")
    try await redirect(true, "third", "running-replacement")
    try step("lap", frames: 120)
    try await redirect(false, "third", "end")
    try step("exit-mid", frames: 11)
    try step("hidden", frames: 12)
    try check(character.orbitOpacity == 0 && character.orbitDots.isEmpty, "Orbit did not retire")
}
