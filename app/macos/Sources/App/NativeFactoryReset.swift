import AppKit
import ChiefCore
import ChiefUI
import Darwin

enum NativeFactoryReset {
    @MainActor static func confirm(in window: NSWindow, locale: DesktopLocale, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = locale.text("将 Chief 恢复到出厂设置？", "Reset Chief to factory settings?")
        alert.informativeText = locale.text(
            "Chief 将停止当前任务，永久清除本配置中的对话、超级线程、标签、设置、草稿、附件和传输副本，以及 Chief 保存的 Agent 会话、用量、命令、阅读记录和缓存。无法撤销。\n\n项目文件、任务工作目录、Git 工作树及外部 Agent 的账户和数据会保留。Chief 将重新启动并打开初始设置。",
            "Chief will stop current tasks and permanently erase this profile’s conversations, Super Threads, tags, settings, drafts, attachment and transfer copies. Chief’s saved agent sessions, usage records, command and reading history, and local caches will also be erased. This cannot be undone.\n\nProject files, task folders, Git worktrees, and external agents’ accounts and data will be kept. Chief will restart and open setup.")
        alert.addButton(withTitle: locale.text("取消", "Cancel")).keyEquivalent = "\r"
        let erase = alert.addButton(withTitle: locale.text("抹掉并重新启动", "Erase and Restart"))
        erase.hasDestructiveAction = true
        erase.keyEquivalent = ""
        alert.beginSheetModal(for: window) { completion($0 == .alertSecondButtonReturn) }
    }

    static func finish(profile: RuntimeProfile, runtime: URL) throws {
        let process = Process()
        process.executableURL = runtime
        process.arguments = ["finish-factory-reset", "--data-dir", profile.dataDirectory.path]
        let diagnostic = Pipe()
        process.standardError = diagnostic
        try process.run()
        let data = diagnostic.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RuntimeError("RESET_FAILED", String(decoding: data, as: UTF8.self))
        }
    }

    // Replace every native task and release the CLOEXEC lifetime lease before
    // maintenance. Reopen the exact profile, even for legacy Alpha installs.
    static func restart(profile: RuntimeProfile, runtime: URL, socket: String?) throws -> Never {
        guard let executable = Bundle.main.executablePath else { throw CocoaError(.executableNotLoadable) }
        var arguments = [executable, "--data-dir", profile.dataDirectory.path, "--runtime", runtime.path]
        if let socket { arguments += ["--automation-socket", socket] }
        let strings = arguments.map { strdup($0) }
        defer { for string in strings { free(string) } }
        guard strings.allSatisfy({ $0 != nil }) else { throw POSIXError(.ENOMEM) }
        var argv = strings + [nil]
        execv(executable, &argv)
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
