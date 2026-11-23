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
            case .matrix: matrix(context, disk)
            case .orbit: break
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
        let lit = accent.mix(with: scheme == .dark ? .white : graphite, by: 0.24)
        let sweep = min(1, time.truncatingRemainder(dividingBy: 2.8) / 2.25) * 15 - 2
        for row in 0..<7 {
            for column in 0..<7 {
                let x = 22 + Double(column - 3) * 5.1, y = 22 + Double(row - 3) * 5.1
                let radius = hypot(x - 22, y - 22)
                guard radius < 20, radius > 11.5 else { continue }
                let distance = (Double(row + column) - sweep) / 1.25
                let intensity = exp(-distance * distance)
                let dot = Path(ellipseIn: .init(x: x - 1, y: y - 1, width: 2, height: 2))
                c.fill(dot, with: .color(ceramic.mix(with: lit, by: 0.19 + 0.80 * intensity)))
            }
        }
    }

    // Stable grain coordinates across frames, appearances and app launches.
    private static func noise(_ index: Int, _ channel: Int) -> Double {
        let value = sin(Double(index + 1) * 73.136 + Double(channel) * 39.417) * 43758.5453
        return value - floor(value)
    }
}
