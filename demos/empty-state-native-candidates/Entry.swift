import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
@testable import ChiefPluginUI

@main @MainActor enum Entry {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--export-previews" {
            guard arguments.count == 2 else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            try export(to: URL(fileURLWithPath: arguments[1], isDirectory: true))
            return
        }
        EmptyStateDemo.main()
    }

    private static func export(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let url = NativeResources.bundle.url(forResource: "ChiefOverviewIdle", withExtension: "png"),
              let skillet = NSImage(contentsOf: url)
        else { throw CocoaError(.fileReadNoSuchFile) }

        let samples = SampleThread.samples(at: .now)
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .light ? "light" : "dark"
            for scenario in EmptyScenario.allCases {
                for candidate in Candidate.allCases {
                    let threads = candidate == .recent ? scenario.recentThreads(in: samples) : []
                    let view = ZStack {
                        palette.canvas.swiftUI
                        StatusWithRecentThreads(status: OffscreenStatus(title: scenario.title, skillet: skillet),
                            scenario: scenario, threads: threads, open: { _ in })
                        ScenarioRail(scenario: scenario, select: { _ in })
                    }
                    .frame(width: 800, height: 500)
                    .foregroundStyle(palette.ink.swiftUI)
                    .environment(\.colorScheme, scheme)
                    .environment(\.locale, Locale(identifier: "en-US"))
                    .environment(\.threadCardUsesFlatMaterials, true)
                    let design = candidate.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
                    let name = "\(scenario.rawValue.lowercased())-\(design)-\(appearance)"
                    let url = directory.appendingPathComponent(name).appendingPathExtension("png")
                    guard let image = ImageRenderer(content: view).cgImage,
                          let file = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
                    else { throw CocoaError(.fileWriteUnknown) }
                    CGImageDestinationAddImage(file, image, nil)
                    guard CGImageDestinationFinalize(file) else { throw CocoaError(.fileWriteUnknown) }
                }
            }
        }
        print(directory.path)
    }
}

// ImageRenderer uses the production asset directly for its AppKit-backed image.
private struct OffscreenStatus: View {
    let title: String
    let skillet: NSImage

    var body: some View {
        VStack(spacing: 8) {
            Color.clear
                .frame(width: 245, height: 85)
                .overlay(alignment: .trailing) {
                    Image(nsImage: skillet)
                        .resizable()
                        .frame(width: 195, height: 85)
                }
                .overlay {
                    ForEach(0..<3) { index in
                        let step = CGFloat(index)
                        Text("z")
                            .font(.system(size: (11 + 2 * step) * 1.25, weight: .bold, design: .rounded))
                            .rotationEffect(.degrees(-9))
                            .position(x: (125 + step * 11) * 1.25, y: (-1 - step * 6) * 1.25)
                    }
                }
                .padding(.top, 31.25)
            Text(title)
                .font(NativeTypography.inter(size: 15, weight: 650))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
