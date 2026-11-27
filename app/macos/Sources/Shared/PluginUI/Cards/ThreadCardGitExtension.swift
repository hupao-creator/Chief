import ChiefPluginAPI
import Foundation
import SwiftUI

struct ThreadCardGitExtension: View {
    let status: HarnessGitStatus
    @Environment(\.locale) private var locale
    private var chinese: Bool { locale.language.languageCode?.identifier == "zh" }
    private var branch: String { status.branch?.string ?? status.head.map { "HEAD · \($0.string.prefix(8))" } ?? "HEAD" }
    private var ink: Color { NativePalette.overview.ink.swiftUI }
    private var secondary: Color { NativePalette.overview.muted.swiftUI }
    private var addedColor: Color { NativePalette.pair(0x238341, 0x6ec487).swiftUI }
    private var deletedColor: Color { NativePalette.pair(0xb44338, 0xe18d82).swiftUI }
    private var lineStatsNotice: String? {
        switch status.lineStatsError {
        case .tooLarge: return chinese ? "行数超出统计上限" : "Line count limit exceeded"
        case .timeout: return chinese ? "行数统计超时" : "Line count timed out"
        case .unavailable, .inaccessible: return chinese ? "行数统计不可用" : "Line counts unavailable"
        case nil: return status.additions == nil || status.deletions == nil
            ? (chinese ? "行数未知" : "Line counts unknown") : nil
        }
    }
    private var staleNotice: String? {
        status.error == nil ? nil : (chinese ? "上次读取，可能已过期" : "Last read; may be stale")
    }
    private var help: String {
        [staleNotice, lineStatsNotice, chinese ? "相对 HEAD 的净改动，含未跟踪文件" : "Net changes against HEAD, including untracked files"]
            .compactMap { $0 }.joined(separator: "; ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if status.recentFiles.isEmpty {
                    summaryOnly
                } else {
                    compactSummary
                }
            }
            .contentShape(Rectangle())
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([chinese ? "Git，\(status.changed) 个文件，\(branch)" : "Git, \(status.changed) files, \(branch)",
                lineStatsNotice ?? "+\(status.additions ?? 0), −\(status.deletions ?? 0)", staleNotice].compactMap { $0 }.joined(separator: "; "))

            if !status.recentFiles.isEmpty {
                VStack(spacing: 5) {
                    ForEach(status.recentFiles, id: \.path) { file in
                        fileRow(file)
                    }
                }
            }
        }
        .opacity(status.error == nil ? 1 : 0.65)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private var summaryOnly: some View {
        VStack(alignment: .leading, spacing: 0) {
            fileCount(size: 30)
            Group {
                if let lineStatsNotice {
                    Text(lineStatsNotice).cardFont(size: 11).foregroundStyle(secondary)
                } else if let additions = status.additions, let deletions = status.deletions {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        lineCount(additions, sign: "+", color: addedColor, size: 17)
                        lineCount(deletions, sign: "−", color: deletedColor, size: 17)
                    }
                }
            }.padding(.top, 6)
            if let staleNotice {
                Text(staleNotice).cardFont(size: 10).foregroundStyle(secondary).padding(.top, 6)
            }
            branchName(size: 11).padding(.top, 8)
        }
    }

    private var compactSummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                fileCount(size: 22)
                Spacer(minLength: 8)
                if let additions = status.additions, let deletions = status.deletions {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        lineCount(additions, sign: "+", color: addedColor, size: 13)
                        lineCount(deletions, sign: "−", color: deletedColor, size: 13)
                    }
                }
            }
            HStack(spacing: 6) {
                branchName(size: 10.5)
                if status.error != nil {
                    Spacer(minLength: 0)
                    Text(chinese ? "可能已过期" : "May be stale")
                        .cardFont(size: 9.5).foregroundStyle(secondary).fixedSize()
                }
            }
        }
    }

    private func branchName(size: CGFloat) -> some View {
        Text(verbatim: branch).cardFont(size: size).foregroundStyle(secondary)
            .lineLimit(1).truncationMode(.middle).help(branch)
    }

    private func fileCount(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            RollingNumberText(value: String(status.changed), fontSize: size, color: ink)
            Text(chinese ? "个文件" : status.changed == 1 ? "file" : "files")
                .cardFont(size: 11).foregroundStyle(secondary)
        }
    }

    private func fileRow(_ file: HarnessGitFileChange) -> some View {
        let path = file.path.string as NSString
        let name = displayPath(path.lastPathComponent)
        let parent = path.deletingLastPathComponent
        let directory = parent.isEmpty ? "." : displayPath(parent)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(verbatim: name).cardMonoFont(size: 11, weight: 570)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    fileDelta(file.additions, sign: "+", color: addedColor)
                    fileDelta(file.deletions, sign: "−", color: deletedColor)
                }
                .fixedSize()
            }
            Text(verbatim: directory).cardMonoFont(size: 9.5)
                .foregroundStyle(secondary).lineLimit(1).truncationMode(.head)
        }
        .padding(.horizontal, 5)
        .frame(height: 33)
        .contentShape(Rectangle())
        .help(file.path.string)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chinese
            ? "\(file.path.string)，新增 \(file.additions) 行，删除 \(file.deletions) 行"
            : "\(file.path.string), \(file.additions) lines added, \(file.deletions) lines removed")
    }

    private func displayPath(_ path: String) -> String {
        var result = ""
        for scalar in path.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) || scalar == "\u{2028}" || scalar == "\u{2029}" {
                result.append("�")
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private func fileDelta(_ value: Int, sign: String, color: Color) -> some View {
        Text(verbatim: "\(sign)\(value)")
            .cardMonoFont(size: 10, weight: 500)
            .foregroundStyle(value == 0 ? secondary : color)
            .frame(minWidth: 23, alignment: .trailing)
    }

    private func lineCount(_ value: Int, sign: String, color: Color, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(sign).cardFont(size: size, monospaced: true)
            RollingNumberText(value: String(value), fontSize: size, color: color)
        }
        .foregroundStyle(color)
    }
}
