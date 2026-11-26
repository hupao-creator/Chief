import AppKit
import ScreenCaptureKit

/// Sample an entire sweep at the two glyphs. Preserve window pixels before
/// testing them so a hidden layer or a compositing regression can be inspected.
@MainActor func captureActivity(in panel: Panel, regions: [String: CGRect], reduced: Bool, card: Bool = false) async throws -> [String: Int] {
    let filter = try await panel.filter()
    let config = panel.configuration()
    config.ignoreGlobalClipSingleWindow = true
    let scale = CGFloat(config.width) / panel.frame.width
    var minima = [String: [UInt8]](), maxima = [String: [UInt8]]()
    for index in 0..<14 {
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        if index == 0 { try savePNG(image, card ? "running-card-edge.png" : "running-filter-activity.png") }
        for (name, frame) in regions {
            let rect = CGRect(x: frame.minX * scale, y: (panel.frame.height - frame.maxY) * scale,
                              width: frame.width * scale, height: frame.height * scale).integral
            guard let crop = image.cropping(to: rect) else { throw ReplayFailure("Missing pixels for " + name) }
            try savePNG(crop, "\(name)-\(index).png")
            let w = crop.width, h = crop.height
            guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
                  let data = context.data else { throw ReplayFailure("Cannot read captured pixels") }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            let rgba = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: w * h * 4))
            if var low = minima.removeValue(forKey: name), var high = maxima.removeValue(forKey: name) {
                for i in rgba.indices {
                    low[i] = min(low[i], rgba[i])
                    high[i] = max(high[i], rgba[i])
                }
                minima[name] = low
                maxima[name] = high
            } else {
                minima[name] = rgba
                maxima[name] = rgba
            }
        }
        if index < 13 { try await pause(225) }
    }
    var counts = [String: Int]()
    for (name, low) in minima {
        let high = maxima[name]!
        let changed = stride(from: 0, to: low.count, by: 4).filter { pixel in
            (0..<3).contains { channel in high[pixel + channel] - low[pixel + channel] > 18 }
        }.count
        counts[name] = changed
    }
    try save(counts, card ? "card-pixel-spans.json" : "pixel-spans.json")
    try check(counts.count == 2 && counts.values.allSatisfy { reduced ? $0 <= 1 : $0 > 1 },
              "Perforation motion disagrees with Reduce Motion (\(reduced)): \(counts)")
    return counts
}
