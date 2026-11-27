import ChiefPluginAPI
import Foundation

/// Chief messages keep their prose and line breaks. Only link syntax is rendered.
package struct NativeMessageText: Equatable, Sendable {
    package enum Part: Equatable, Sendable {
        case text(String)
        case web(label: String, url: URL)
        case execution(label: String?, url: URL, reference: ApplicationExecutionRef)

        fileprivate var isLink: Bool {
            if case .text = self { return false }
            return true
        }
    }

    package let parts: [Part]
    package var hasLinks: Bool { parts.contains(where: \.isLink) }

    private static let bareLinks: NSRegularExpression = {
        let prefix = #"(?:https?://(?:\[[0-9a-f:.]+\])?|www\.|(?:chief|mokusei)://)"#
        let ordinary = #"[^\s<>\[\]"“”‘’（）［］｛｝，。！？；、：《》「」『』【】,;\x60]"#
        // A comma or semicolon may belong to the URL or separate two adjacent addresses.
        return try! NSRegularExpression(pattern: #"(?i)(?<![a-z0-9_:/@])\#(prefix)\#(ordinary)*+(?:[,;](?!\#(prefix))\#(ordinary)*+)*+"#)
    }()

    package init(_ text: String) {
        guard text.contains("://") || text.range(of: "www.", options: .caseInsensitive) != nil else {
            parts = []
            return
        }
        let source = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let raw = source as NSString
        let regions = MarkdownSourceMap.ranges(source, visibleText: false, includeLinks: true)
            .sorted { $0.range.location < $1.range.location }
        var output: [Part] = []
        var cursor = 0
        func appendLink(_ part: Part, in range: NSRange) {
            if cursor < range.location {
                output.append(.text(raw.substring(with: NSRange(location: cursor, length: range.location - cursor))))
            }
            output.append(part)
            cursor = NSMaxRange(range)
        }
        func scanBareLinks(from start: Int, to end: Int) {
            guard start < end else { return }
            for match in Self.bareLinks.matches(in: source, range: NSRange(location: start, length: end - start)) {
                var value = raw.substring(with: match.range)
                var unmatchedClosers = value.count(where: { $0 == ")" }) - value.count(where: { $0 == "(" })
                while let last = value.last {
                    if last == ")", unmatchedClosers > 0 { unmatchedClosers -= 1 }
                    else if !".,:;!?'".contains(last) { break }
                    value.removeLast()
                }
                if let part = Self.link(value, label: nil, displayedURL: value) {
                    appendLink(part, in: NSRange(location: match.range.location, length: value.utf16.count))
                }
            }
        }
        var endOfRegion = 0
        for region in regions where region.range.location >= endOfRegion {
            scanBareLinks(from: endOfRegion, to: region.range.location)
            if let link = region.link {
                let isAutolink = raw.substring(with: region.range).hasPrefix("<")
                let label = isAutolink || link.label.isEmpty ? nil : link.label
                let display = link.label.isEmpty ? link.destination : link.label
                if let part = Self.link(link.destination, label: label, displayedURL: display) {
                    appendLink(part, in: region.range)
                }
            }
            endOfRegion = NSMaxRange(region.range)
        }
        scanBareLinks(from: endOfRegion, to: raw.length)
        if cursor < raw.length { output.append(.text(raw.substring(from: cursor))) }
        parts = output
    }

    private static func link(_ destination: String, label: String?, displayedURL: String) -> Part? {
        if let url = URL(string: destination, encodingInvalidCharacters: false),
           let reference = ApplicationExecutionLink.parse(url) {
            return .execution(label: label, url: url, reference: reference)
        }
        let web = destination.lowercased().hasPrefix("www.") ? "http://" + destination : destination
        guard let url = URL(string: web), isWebURL(url) else { return nil }
        return .web(label: label ?? displayedURL, url: url)
    }

    package static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return false }
        return true
    }
}
