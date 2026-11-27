import SwiftUI

enum VoicePhase: String {
    case idle, connecting, listening, speaking, muted
}

struct VoiceOrb: View {
    let phase: VoicePhase
    let microphoneMuted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clockOrigin = Date.now

    var body: some View {
        CloudDisk(activity: phase.activity, runs: !reduceMotion && phase.activity > 0, origin: clockOrigin)
            // Fade the pigment into the round glass, leaving its refractive rim exposed.
            .mask(RadialGradient(stops: [.init(color: .white, location: 0.78),
                                          .init(color: .white.opacity(0.9), location: 0.90),
                                          .init(color: .clear, location: 1)],
                                 center: .center, startRadius: 0, endRadius: VoiceDock.diameter / 2))
            .saturation(microphoneMuted ? 0.26 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.30), value: phase)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.30), value: microphoneMuted)
            .accessibilityHidden(true).allowsHitTesting(false)
    }
}

private struct CloudDisk: View, @MainActor Animatable {
    var activity: Double
    let runs: Bool
    let origin: Date

    var animatableData: Double {
        get { activity }
        set { activity = newValue }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !runs)) { tick in
            let seconds = runs ? max(0, tick.date.timeIntervalSince(origin)) : 0
            let image = activity == 0 ? CloudWash.resting : CloudWash.image(time: seconds, activity: Float(activity))
            Image(decorative: image, scale: 2)
                .resizable()
                .interpolation(.high)
        }
    }
}

// At Retina scale each sample covers one screen pixel. The stationary disk and paper grain
// are shared. Only an active voice phase advects the pigment across the small raster.
private enum CloudWash {
    private static let side = 80
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    static let resting = image(time: 0, activity: 0)

    private static let paper: [Float] = {
        var seed: UInt32 = 0xC105ED
        let white = (0..<(side * side)).map { _ -> Float in
            seed = 1_664_525 &* seed &+ 1_013_904_223
            return Float(seed >> 8) / 8_388_608 - 1
        }
        func noise(x: Int, y: Int, cell: Int) -> Float {
            let count = side / cell
            let col = x / cell, row = y / cell
            let u = smooth(Float(x % cell) / Float(cell))
            let v = smooth(Float(y % cell) / Float(cell))
            let a = white[row * side + col]
            let b = white[row * side + (col + 1) % count]
            let c = white[((row + 1) % count) * side + col]
            let d = white[((row + 1) % count) * side + (col + 1) % count]
            return (a + (b - a) * u) * (1 - v) + (c + (d - c) * u) * v
        }
        return (0..<(side * side)).map { index in
            let x = index % side, y = index / side
            return 0.41 * noise(x: x, y: y, cell: 8) + 0.29 * noise(x: x, y: y, cell: 4)
                + 0.19 * noise(x: x, y: y, cell: 2) + 0.11 * white[index]
        }
    }()

    private static func smooth(_ value: Float) -> Float {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    static func image(time: Double, activity: Float) -> CGImage {
        let t = Float(time)
        let drift = (t * 2).truncatingRemainder(dividingBy: Float(side))
        let paperOffset = Int(drift), fraction = drift - Float(paperOffset)
        let ice = SIMD3<Float>(236, 241, 254)
        var rgba = Data(count: side * side * 4)
        rgba.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            for col in 0..<side {
                let x = (Float(col) + 0.5) / Float(side)
                let wave = 0.72 * cos(5.1 * (x - 0.36) - 1.12 * t) + 0.28 * cos(8.1 * (x - 0.38) - 0.83 * t)
                let restHeight = 0.718 + 0.225 * exp(-10.0 * x * x) + 0.019 * sin(7.4 * x - 0.8)
                let crest = restHeight - activity * (0.105 + 0.32 * wave)
                let spread = 0.071 + activity * (0.063 + 0.033 * wave)
                let plumeX = (x - 0.24 - activity * 0.10 * sin(t)) / 0.19
                let plume = exp(-0.5 * plumeX * plumeX)
                let lower = SIMD3<Float>(182, 200, 250) + SIMD3<Float>(56, 46, 5) * (activity * max(0, wave))
                let sampleX = (col + paperOffset) % side
                for row in 0..<side {
                    let y = (Float(row) + 0.5) / Float(side)
                    let offset = row * side
                    let grain = paper[offset + sampleX] * (1 - fraction) + paper[offset + (sampleX + 1) % side] * fraction
                    let distance = y - crest + grain * (0.016 + 0.030 * plume + 0.018 * activity)
                    let depth = y + 0.065 * (0.5 - x)
                    let blue = SIMD3<Float>(38, 85, 226) + SIMD3<Float>(86, 84, 23) * depth
                    let under = blue + (lower - blue) * smooth((distance + 0.17) / 0.34)
                    let ridge = distance / spread
                    let wisp = (distance + 0.085 + 0.115 * plume) / (0.050 + 0.025 * plume)
                    let mist = (0.08 + 0.22 * plume) * (1 + 0.72 * grain) * exp(-0.5 * wisp * wisp)
                    let pigment = 0.92 * exp(-0.5 * ridge * ridge)
                    let color = under + (ice - under) * (mist + (1 - mist) * pigment)
                    let i = (offset + col) * 4
                    bytes[i] = UInt8(clamping: Int(color.x.rounded()))
                    bytes[i + 1] = UInt8(clamping: Int(color.y.rounded()))
                    bytes[i + 2] = UInt8(clamping: Int(color.z.rounded()))
                    bytes[i + 3] = 255
                }
            }
        }
        let provider = CGDataProvider(data: rgba as CFData)!
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
}

extension VoicePhase {
    var activity: Double {
        switch self {
        case .idle, .connecting, .muted: 0
        case .listening: 0.23
        case .speaking: 1
        }
    }
}
