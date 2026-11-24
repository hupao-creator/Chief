import AppKit
import ChiefPluginUI
import CoreText
import SwiftUI

/// Use the same system glyph as the tag, including joined emoji and skin tones.
@MainActor enum OverviewTagTint {
    private final class Swatch {
        let color: Color
        init(_ color: Color) { self.color = color }
    }

    private static let cache: NSCache<NSString, Swatch> = {
        let cache = NSCache<NSString, Swatch>()
        cache.countLimit = 256
        return cache
    }()

    static func color(for emoji: String?) -> Color {
        let accent = NativePalette.overview.accent.swiftUI
        guard let emoji, !emoji.isEmpty else { return accent }
        let key = emoji as NSString
        if let swatch = cache.object(forKey: key) { return swatch.color }
        let color = glyphColor(emoji) ?? accent
        cache.setObject(Swatch(color), forKey: key)
        return color
    }

    private struct HueBand {
        var count = 0
        var red = 0.0, green = 0.0, blue = 0.0

        mutating func add(_ r: Double, _ g: Double, _ b: Double) {
            count += 1
            red += r
            green += g
            blue += b
        }
    }

    private static func glyphColor(_ emoji: String) -> Color? {
        let side = 40
        let format = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: space, bitmapInfo: format), let data = context.data else { return nil }
        let text = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: 31)])
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetImageBounds(line, context)
        guard !bounds.isEmpty else { return nil }
        context.textPosition = CGPoint(x: CGFloat(side) / 2 - bounds.midX, y: CGFloat(side) / 2 - bounds.midY)
        CTLineDraw(line, context)

        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var bands = Array(repeating: HueBand(), count: 24)
        var colored = 0, visible = 0
        var luminance = 0.0
        for i in stride(from: 0, to: side * side * 4, by: 4) {
            let alpha = Double(bytes[i + 3])
            guard alpha >= 160 else { continue }
            let r = Double(bytes[i]) / alpha, g = Double(bytes[i + 1]) / alpha, b = Double(bytes[i + 2]) / alpha
            visible += 1
            luminance += 0.2126 * r + 0.7152 * g + 0.0722 * b
            let peak = max(r, g, b), chroma = peak - min(r, g, b)
            guard chroma >= 0.10, chroma >= 0.15 * peak else { continue }
            let angle = atan2(sqrt(3.0) * (g - b), 2 * r - g - b)
            let bin = (Int((angle * 12 / .pi).rounded()) + 24) % 24
            bands[bin].add(r, g, b)
            colored += 1
        }
        guard visible > 0 else { return nil }
        // Tiny colored details on a monochrome flag or tool do not recolor its glass.
        if colored * 6 < visible {
            let gray = min(0.72, max(0.30, luminance / Double(visible)))
            return Color(.sRGB, red: gray, green: gray, blue: gray)
        }
        // Neighboring bins keep one painted area together across shading and the hue wrap.
        func population(_ i: Int) -> Int {
            bands[(i + 23) % 24].count + 2 * bands[i].count + bands[(i + 1) % 24].count
        }
        let center = bands.indices.max { population($0) < population($1) }!
        let neighbors = [bands[(center + 23) % 24], bands[center], bands[(center + 1) % 24]]
        let count = Double(neighbors.reduce(0) { $0 + $1.count })
        return Color(.sRGB, red: neighbors.reduce(0) { $0 + $1.red } / count,
                     green: neighbors.reduce(0) { $0 + $1.green } / count,
                     blue: neighbors.reduce(0) { $0 + $1.blue } / count)
    }
}
