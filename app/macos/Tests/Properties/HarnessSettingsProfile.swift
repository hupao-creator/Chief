import Foundation
import ChiefCore
import ChiefPluginAPI
@testable import ChiefUI

/// The child has no connection to an installed Chief or native account. Opening
/// its SQLite file afresh for each command also makes every read a cold read.
@MainActor final class HarnessSettingsProfile {
    let executable: URL
    let directory: URL
    var failedProbe: String?
    var failedCatalog: String?
    var heldProbe: String?
    private var releaseProbe: CheckedContinuation<Void, Never>?

    func finishProbe() {
        heldProbe = nil
        releaseProbe?.resume()
        releaseProbe = nil
    }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../..").standardizedFileURL

    init(executable: URL, directory: URL) {
        self.executable = executable
        self.directory = directory
    }

    static func buildPeer(in directory: URL) throws -> URL {
        let binary = directory.appendingPathComponent("settingspeer")
        let root = repository
        let process = Process()
        process.executableURL = root.appendingPathComponent("scripts/go.sh")
        process.currentDirectoryURL = root
        process.arguments = ["build", "-o", binary.path, "./tools/verification/pbt/settingspeer"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw PropertyFailure("settings peer build failed") }
        return binary
    }

    func invoke(_ channel: String, _ args: [JSONValue] = []) throws -> JSONValue {
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.currentDirectoryURL = directory
        process.environment = ["HOME": directory.path, "TMPDIR": directory.path, "PATH": ""]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        let request = JSONValue.object(["channel": .text(channel), "args": .array(args),
                                        "failProbe": .text(failedProbe ?? ""), "failCatalog": .text(failedCatalog ?? "")])
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: request.encodedData())
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RuntimeError("SETTINGS_PEER", channel + " " + String(decoding: data, as: UTF8.self))
        }
        return try JSONValue(data: data)
    }

    func save(_ value: JSONValue, revision: Int) throws -> NativeSettingsSaveResult {
        let result = try invoke("app:update-settings", [.object(["settings": value, "expectedSettingsRevision": .integer(revision)])])
        guard let saved = result["settings"], let revision = result["settingsRevision"]?.intValue else {
            throw PropertyFailure("invalid save receipt")
        }
        switch result["status"] {
        case .text("saved"): return .saved(settings: saved, revision: revision)
        case .text("conflict"): return .conflict(settings: saved, revision: revision)
        default: throw PropertyFailure("unknown save receipt")
        }
    }

    func makeModel() throws -> NativeSettingsModel {
        let state = try invoke("state:load")
        guard let settings = state["settings"], let revision = state["settingsRevision"]?.intValue else {
            throw PropertyFailure("missing profile settings")
        }
        let model = NativeSettingsModel(settings: settings, revision: revision,
            save: { try self.save($0, revision: $1) },
            loadInstallations: { try self.invoke("harness:detect-installations") },
            installHarness: { _ in throw PropertyFailure("unexpected installation") },
            loadInstallation: { id in
                if self.heldProbe == id {
                    await withCheckedContinuation { self.releaseProbe = $0 }
                }
                return try self.invoke("harness:detect-installation", [.text(id)])
            })
        model.receive(snapshot: state, runtimeAvailable: true)
        return model
    }

    func session(_ plugin: AnyHarnessPlugin, model: NativeSettingsModel) -> HarnessSettingsSession {
        plugin.makeSettingsSession(publishPresentations: true, load: { refresh in
            let response = try self.invoke("harness:settings-presentation", [.object([
                "scope": .text("global"), "harnessId": .string(plugin.descriptor.id),
                "executionOwner": .text("moku"), "refresh": .bool(refresh)
            ])])
            guard response["executionSnapshotError"] == nil, let value = response["value"] else {
                throw PropertyFailure("unexpected snapshot error: \(response)")
            }
            return value
        }, onError: { model.operationError = $0.localizedDescription })
    }
}
