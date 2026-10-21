import AppKit

@MainActor
struct ObsidianTextBuffer {
    private let app: NSRunningApplication
    private let executable: URL
    let snapshot: ObsidianEditorScript.Snapshot

    private struct Payload: Encodable {
        let snapshot: ObsidianEditorScript.Snapshot
        let replacement: String
    }

    static func capture(in app: NSRunningApplication) async throws -> Self {
        guard app.bundleIdentifier == "md.obsidian", let executable = app.bundleURL?
            .appendingPathComponent("Contents/MacOS/obsidian-cli")
        else { throw Failure.unavailable }
        let output = try await evaluate(ObsidianEditorScript.capture, executable: executable)
        let snapshot = try JSONDecoder().decode(ObsidianEditorScript.Snapshot.self, from: output)
        guard snapshot.from >= 0, snapshot.to >= snapshot.from, snapshot.to <= snapshot.text.utf16.count,
            snapshot.text.utf16.count <= 1_000_000, Range(snapshot.selection, in: snapshot.text) != nil
        else { throw Failure.unavailable }
        return Self(app: app, executable: executable, snapshot: snapshot)
    }

    func replace(with text: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = directory.appendingPathComponent("edit.json")
        try JSONEncoder().encode(Payload(snapshot: snapshot, replacement: text)).write(to: payload)
        guard !app.isTerminated else { throw Failure.unavailable }
        app.activate()
        try await Task.sleep(for: .milliseconds(120))
        guard app.isActive, !Task.isCancelled else { throw Failure.unavailable }
        let result = try await Self.evaluate(
            ObsidianEditorScript.apply(payloadPath: payload.path), executable: executable, vault: snapshot.vault)
        struct Receipt: Decodable { let changed: Bool }
        guard try JSONDecoder().decode(Receipt.self, from: result).changed else { throw Failure.unavailable }
    }

    private enum Failure: Error { case unavailable }

    private static func evaluate(_ script: String, executable: URL, vault: String? = nil) async throws -> Data {
        let arguments = (vault.map { ["vault=" + $0] } ?? []) + ["eval", "code=" + script]
        let result = try await ToolRunner.run(executable, arguments, timeout: 5,
            workingDirectory: FileManager.default.temporaryDirectory)
        guard result.succeeded,
            let line = result.output.split(separator: "\n").last(where: { $0.hasPrefix("=> ") })
        else { throw Failure.unavailable }
        return Data(line.dropFirst(3).utf8)
    }
}
