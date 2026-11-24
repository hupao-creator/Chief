import AppKit

// The lower inner face clears the 19pt emoji, label, corner badge and reflected rim.
func filterFaceRGB(_ pixels: NSBitmapImageRep, at frame: CGRect, scale: CGFloat) -> [Double] {
    let cx = frame.minX + frame.height / 2
    let cy = frame.midY + 12
    var channels = Array(repeating: [Double](), count: 3)
    for dx in [-3, 0, 3] {
        for dy in [-0.5, 0.0, 0.5] {
            let x = Int((cx + CGFloat(dx)) * scale), y = Int((cy + dy) * scale)
            guard let color = pixels.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            channels[0].append(color.redComponent)
            channels[1].append(color.greenComponent)
            channels[2].append(color.blueComponent)
        }
    }
    return channels.map { $0.isEmpty ? 0 : $0.sorted()[$0.count / 2] }
}
