import AppKit
@testable import ChiefUI

/// The panel is fully offscreen. Drive both native controllers with the same
/// display-frame deltas so each interrupted frame has an uninterrupted peer.
@MainActor func orbitFadeFrames(panel: Panel, character: NativeMokuCharacterMotion,
                               setRunning: (Bool, String) async throws -> Void) async throws {
    let reference = NativeMokuCharacterMotion()
    let bounds = CGRect(x: 0, y: 0, width: 208, height: 84)
    var rows = [[String: Any]]()
    var elapsed = 0.0

    func capture(_ event: String, image: Bool) throws {
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
        let story = ReferenceRunningGeometry.sample(milliseconds: elapsed,
            capsuleSize: input.capsuleSize, cornerRadius: input.cornerRadius)
        let expectedArea = story.dots.reduce(0.0) { $0 + $1.opacity } * .pi * 2.5 * 2.5 * alpha
        try check(abs(area - expectedArea) < 2, "Painted dot area: " + event)
        try check(dots.count == (alpha > 0 ? 3 : 0), "Visible dot count: " + event)
        for (index, dot) in dots.enumerated() {
            let peer = reference.orbitDots[index], authored = story.dots[index]
            try check(hypot(dot.x - peer.x, dot.y - peer.y) < 0.001, "Orbit phase changed: " + event)
            try check(hypot(dot.x - (authored.x - 320) * 0.075, dot.y - (authored.y - 300) * 0.075) < 0.001
                && abs(dot.opacity - authored.opacity) < 0.001, "Authored motion diverged: " + event)
        }
    }

    func step(_ event: String, frames: Int) throws {
        for frame in 1...frames {
            let prior = character.orbitOpacity
            elapsed += 25
            character.advanceFrame(milliseconds: 25)
            reference.advanceFrame(milliseconds: 25)
            try capture(event, image: frame == frames)
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
        try capture(event, image: false)
    }

    try await setRunning(true, "first")
    guard let first = character.input else { throw ReplayFailure("Missing initial run") }
    reference.configure(first)
    try capture("start", image: true)
    try step("enter-mid", frames: 11)
    try await redirect(false, "first", "interrupt-entry")
    try step("early-exit-mid", frames: 4)
    try await redirect(true, "second", "reverse-before-hidden")
    try step("reverse-mid", frames: 8)
    try step("fully-visible", frames: 16)
    try check(character.orbitOpacity == 1, "Orbit never reached full opacity")
    try await redirect(true, "third", "running-replacement")
    // The first 39 frames cover 975ms. Sample the top of the lap, then
    // the resting row and the narrowest lids in the recovery.
    try step("half-lap", frames: 158)
    try check(character.orbitDots[1].y < -27, "Middle dot did not reach the top of the capsule")
    try step("landing", frames: 86)
    try check(character.orbitDots.allSatisfy { abs($0.y - 27.5) < 0.001 }, "Dots did not settle below the capsule")
    let openHeight = character.pose.eye("l").h
    try step("recovery-squint", frames: 12)
    try check(character.pose.eye("l").h < openHeight * 0.25, "Missing post-lap squint")
    try step("next-relay", frames: 30)
    try check(character.pose.eye("l").h >= openHeight * 0.99 && character.orbitDots[0].y < 27.4,
              "Eyes did not reopen for the next relay")
    try await redirect(false, "third", "end")
    try step("exit-mid", frames: 11)
    try step("hidden", frames: 12)
    try check(character.orbitOpacity == 0 && character.orbitDots.isEmpty, "Orbit did not retire")
}
