import ChiefPluginUI
import SwiftUI

/// Material artwork lives in a 44-point disc underneath the unmodified emoji.
struct BadgeFinish: View {
    let style: BadgeStyle
    let time: Double
    @Environment(\.threadCardProviderColor) private var accent
    @Environment(\.colorScheme) private var scheme
    private let face = NativePalette.overview.surfaceStrong.swiftUI
    private let graphite = Color(red: 0.13, green: 0.15, blue: 0.18)

    var body: some View {
        Canvas { context, size in
            var context = context
            let diameter = ThreadCardProviderStatus.diameter
            context.scaleBy(x: size.width / diameter, y: size.height / diameter)
            let disk = Path(ellipseIn: CGRect(x: 0, y: 0, width: diameter, height: diameter))
            context.clip(to: disk)
            switch style {
            case .titanium: titanium(context, disk)
            case .latitude: latitude(context, disk)
            case .split, .duet, .steps: matrix(context, disk)
            case .orbit, .matrix: break
            }
        }
    }

    private func titanium(_ c: GraphicsContext, _ disk: Path) {
        let angle = time * 2 * .pi / 3.8
        let center = 22 + 17 * sin(angle)
        let metal = face.mix(with: graphite, by: scheme == .dark ? 0.35 : 0.17)
        let low = metal.mix(with: accent, by: 0.16)
        let silver = metal.mix(with: .white, by: scheme == .dark ? 0.48 : 0.84)
        let reflection = Gradient(stops: [
            .init(color: low, location: 0), .init(color: metal, location: 0.32),
            .init(color: silver, location: 0.58), .init(color: low, location: 0.86)
        ])
        c.fill(disk, with: .linearGradient(reflection, startPoint: .init(x: center - 18, y: 0),
                                           endPoint: .init(x: center + 13, y: 39)))
        // Short, irregular machining marks stay attached to the face as the light travels.
        for i in 0..<100 {
            let x = Self.noise(i, 1) * 48 - 4, y = Self.noise(i, 2) * 44
            var mark = Path()
            mark.move(to: .init(x: x, y: y))
            mark.addLine(to: .init(x: x + 2 + 10 * Self.noise(i, 3), y: y - 0.65))
            c.stroke(mark, with: .color(i.isMultiple(of: 3) ? .black.opacity(0.14) : .white.opacity(0.22)),
                     lineWidth: 0.35)
        }
        c.stroke(disk, with: .color(silver.opacity(0.70)), lineWidth: 1.4)
    }

    private func latitude(_ c: GraphicsContext, _ disk: Path) {
        let slate = graphite.mix(with: accent, by: 0.18)
        let frost = face.mix(with: .white, by: 0.58).mix(with: accent, by: 0.12)
        c.fill(disk, with: .color(slate))
        var surface = c
        surface.translateBy(x: 22, y: 22)
        surface.rotate(by: .degrees(-12))
        surface.translateBy(x: -22, y: -22)
        let crest = (time.truncatingRemainder(dividingBy: 2.9) / 2.9) * 11 - 2
        for row in 0..<8 {
            let y = Double(row) * 7 - 12
            var band = Path()
            band.move(to: .init(x: -5, y: y))
            band.addQuadCurve(to: .init(x: 49, y: y), control: .init(x: 22, y: y + 12))
            band.addLine(to: .init(x: 49, y: y + 5.8))
            band.addQuadCurve(to: .init(x: -5, y: y + 5.8), control: .init(x: 22, y: y + 17.8))
            band.closeSubpath()
            let distance = (Double(row) - crest) / 1.15
            let light = 0.14 + 0.60 * exp(-distance * distance)
            let silver = slate.mix(with: frost, by: light)
            surface.fill(band, with: .linearGradient(.init(colors: [silver, silver.mix(with: slate, by: 0.4)]),
                startPoint: .init(x: 4, y: 0), endPoint: .init(x: 44, y: 12)))
        }
    }

    private func matrix(_ c: GraphicsContext, _ disk: Path) {
        let ceramic = face.mix(with: graphite, by: scheme == .dark ? 0.20 : 0.08)
        c.fill(disk, with: .color(ceramic))
        let unlit = ceramic.mix(with: NativePalette.overview.ink.swiftUI, by: 0.18)
        let radius = disk.boundingRect.midX
        let dotRadius = 1.0
        // Eight intervals place the four axial holes tangent to the disk.
        // The circular Canvas clip also trims neighboring holes across the rim.
        let pitch = (radius - dotRadius) / 4
        for row in -4...4 {
            for column in -4...4 {
                let dx = Double(column) * pitch, dy = Double(row) * pitch
                guard hypot(dx, dy) < radius + dotRadius else { continue }
                let intensity = dotLight(row: row, column: column)
                let dot = Path(ellipseIn: .init(x: radius + dx - dotRadius, y: radius + dy - dotRadius,
                                                width: 2 * dotRadius, height: 2 * dotRadius))
                c.fill(dot, with: .color(unlit.mix(with: accent, by: intensity)))
            }
        }
    }

    private func dotLight(row: Int, column: Int) -> Double {
        switch style {
        case .split:
            let phase = time.truncatingRemainder(dividingBy: 3.1) / 3.1
            let distance = Double(abs(column)) - (min(1, phase / 0.80) * 7 - 1)
            return exp(-2.25 * distance * distance)
        case .duet:
            let phase = time.truncatingRemainder(dividingBy: 2.8)
            let left = column < 0
            let dx = Double(column - (left ? -2 : 2))
            let dy = Double(row - (left ? -1 : 1))
            let weight = exp(-0.19 * (dx * dx + dy * dy))
            let arrival = left ? 0.50 : 1.55
            let beat = (phase - arrival - 0.06 * dy) / (left ? 0.23 : 0.36)
            return weight * exp(-beat * beat)
        case .steps:
            let tick = time.truncatingRemainder(dividingBy: 2.8) / 0.22
            // Mirror the stair across the center so both trails stay outside the glyph.
            let step = Self.stair.firstIndex { point in
                (point.x == column && point.y == row) || (-point.x == column && -point.y == row)
            }
            guard let step else { return 0 }
            let age = tick - Double(step)
            if age < 0 { return max(0, 1 + age * 5) }
            return exp(-1.25 * age)
        default:
            return 0
        }
    }

    private static let stair: [(x: Int, y: Int)] = [
        (-1, -4), (0, -4), (1, -4), (1, -3), (2, -3), (2, -2),
        (3, -2), (3, -1), (4, -1), (4, 0), (4, 1)
    ]

    // Stable grain coordinates across frames, appearances and app launches.
    private static func noise(_ index: Int, _ channel: Int) -> Double {
        let value = sin(Double(index + 1) * 73.136 + Double(channel) * 39.417) * 43758.5453
        return value - floor(value)
    }
}
