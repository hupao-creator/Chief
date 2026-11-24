import SwiftUI

/// Dot centres in points relative to the centre of the compact capsule.
struct NativeMokuRunningGeometry {
    private let path: Path
    private let size: CGSize

    init(size: CGSize, cornerRadius: CGFloat) {
        self.size = size
        path = Self.orbitPath(in: size, cornerRadius: cornerRadius)
    }

    private func point(lap: Double, index: Int) -> CGPoint {
        let phase = lap + Double(1 - index) * 0.17 / (2 * .pi)
        let point = path.trimmedPath(from: 0, to: phase - floor(phase)).currentPoint
            ?? CGPoint(x: size.width / 2, y: size.height + 5.5)
        return CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
    }

    func gaze(milliseconds: Double, direct: Bool) -> MokuRunningFrame.Eyes {
        let lap = milliseconds / (MokuRunningStory.orbitBeats * MokuRunningStory.beatMS)
        let lead = point(lap: lap, index: 0)
        var eyes = MokuRunningStory.orbitEyes(direction: CGPoint(x: lead.x / (size.width / 2 + 5.5),
            y: lead.y / (size.height / 2 + 5.5)), progress: lap - floor(lap))
        // The authored lid recovery and resident blink still play over the
        // tracking gaze. Only its direction follows the compact contour.
        let beat = milliseconds / MokuRunningStory.beatMS + (direct ? 1.22 : 0)
        eyes.scaleY -= MokuRunningStory.recoverySquint(at: beat.truncatingRemainder(dividingBy: MokuRunningStory.cycleBeats))
        return eyes
    }

    func dots(milliseconds: Double) -> [MokuRunningFrame.Dot] {
        let lap = milliseconds / (MokuRunningStory.orbitBeats * MokuRunningStory.beatMS)
        let palettePhase = milliseconds / (MokuRunningStory.cycleBeats * MokuRunningStory.beatMS)
        return (0..<3).map { index in
            let center = point(lap: lap, index: index)
            return .init(x: center.x, y: center.y,
                         opacity: 1, color: MokuRunningStory.color(palettePhase + Double(index) / 3))
        }
    }

    private static func orbitPath(in size: CGSize, cornerRadius: CGFloat) -> Path {
        let orbitOffset: CGFloat = 5.5
        // Offset the visible glass contour by both dot radius and clear space.
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: -orbitOffset, dy: -orbitOffset)
        let radius = max(0, min(cornerRadius, min(size.width, size.height) / 2)) + orbitOffset
        return Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            for (center, start) in [
                (CGPoint(x: rect.minX + radius, y: rect.maxY - radius), 90.0),
                (CGPoint(x: rect.minX + radius, y: rect.minY + radius), 180.0),
                (CGPoint(x: rect.maxX - radius, y: rect.minY + radius), 270.0),
                (CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), 360.0)
            ] {
                path.addArc(center: center, radius: radius, startAngle: .degrees(start),
                            endAngle: .degrees(start + 90), clockwise: false)
            }
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
    }
}
