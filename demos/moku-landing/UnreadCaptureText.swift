import Foundation
import Vision

// The window has exited. Check its saved pixels with the same recognition settings for each locale.
struct Capture: Encodable {
    let screenshot: String
    let expected: String
    let lines: [String]
    let seconds: Double
    let passed: Bool
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
var captures: [Capture] = []
for (name, languages, expected) in [
    ("unread-empty-en-US.png", ["en-US"], "No unread conversations"),
    ("unread-empty-zh-CN.png", ["zh-Hans", "en-US"], "没有未读会话"),
] {
    let image = directory.appendingPathComponent(name)
    let request = VNRecognizeTextRequest()
    request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    request.recognitionLanguages = languages
    request.minimumTextHeight = 0.008
    let start = ProcessInfo.processInfo.systemUptime
    try VNImageRequestHandler(url: image).perform([request])
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    let passed = lines.contains { $0.replacingOccurrences(of: " ", with: "") == expected.replacingOccurrences(of: " ", with: "") }
    captures.append(Capture(screenshot: name, expected: expected, lines: lines,
                            seconds: ProcessInfo.processInfo.systemUptime - start, passed: passed))
}
FileHandle.standardOutput.write(try JSONEncoder().encode(captures))
exit(captures.allSatisfy(\.passed) ? EXIT_SUCCESS : EXIT_FAILURE)
