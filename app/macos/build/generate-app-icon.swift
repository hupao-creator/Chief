import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func iconPNG(source: CGImageSource, pixels: Int) throws -> Data {
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: pixels,
    ]
    guard let raster = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
          raster.width == pixels, raster.height == pixels else {
        throw NSError(domain: "AppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot render \(pixels)-pixel icon"])
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "AppIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot create PNG destination"])
    }
    CGImageDestinationAddImage(destination, raster, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "AppIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    return data as Data
}

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: generate-app-icon /path/to/chief-logo.webp /path/to/AppIcon.icns")
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else {
    fatalError("Cannot read artwork at \(input.path)")
}
let output = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
let manager = FileManager.default
let temporary = manager.temporaryDirectory.appendingPathComponent("chief-icon-\(UUID().uuidString)")
let iconset = temporary.appendingPathComponent("AppIcon.iconset")
try manager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: temporary) }
try manager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

var images: [Int: Data] = [:]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        if images[pixels] == nil { images[pixels] = try iconPNG(source: source, pixels: pixels) }
        let suffix = scale == 2 ? "@2x" : ""
        try images[pixels]!.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
let staged = temporary.appendingPathComponent("AppIcon.icns")
process.arguments = ["--convert", "icns", "--output", staged.path, iconset.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "AppIcon", code: Int(process.terminationStatus),
                  userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}
// Leave the previous asset intact if the platform encoder fails.
try Data(contentsOf: staged).write(to: output, options: .atomic)
print("Generated \(output.lastPathComponent) from \(input.lastPathComponent)")
