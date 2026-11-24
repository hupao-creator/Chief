import SwiftUI

/// Dot centres in points relative to the centre of the compact capsule.
struct NativeMokuRunningGeometry {
    private let path: Path
    private let size: CGSize

    init(size: CGSize, cornerRadius: CGFloat) {
        self.size = size
        path = Self.orbitPath(in: size, cornerRadius: cornerRadius)
    }

    func sample(milliseconds: Double) -> MokuRunningFrame {
        // The story uses a 640-point view box. The Dock paints in capsule-local points.
        let scale = 0.075
        let radii = CGSize(width: size.width / 2 + 5.5, height: size.height / 2 + 5.5)
        var frame = MokuRunningStory.sample(time: milliseconds / MokuRunningStory.beatMS,
            restingY: 300 + radii.height / scale, restingSpacing: 8 / scale,
            orbitRadii: CGSize(width: radii.width / scale, height: radii.height / scale)) { angle in
            let lap = (angle - .pi / 2) / (2 * .pi)
            let point = path.trimmedPath(from: 0, to: lap - floor(lap)).currentPoint
                ?? CGPoint(x: size.width / 2, y: size.height + 5.5)
            return CGPoint(x: 320 + (point.x - size.width / 2) / scale,
                           y: 300 + (point.y - size.height / 2) / scale)
        }
        for index in frame.dots.indices {
            frame.dots[index].x = (frame.dots[index].x - 320) * scale
            frame.dots[index].y = (frame.dots[index].y - 300) * scale
        }
        return frame
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
