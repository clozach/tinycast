import Foundation
import Darwin

@MainActor @Observable
final class TeachStore {
    private let fileURL: URL
    private(set) var targets: [TaughtTarget] = []
    private(set) var loadError: String?
    private(set) var revision = 0
    var onChange: (() -> Void)?

    init(fileURL: URL) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let decoded = try JSONDecoder().decode([TaughtTarget].self, from: Data(contentsOf: fileURL))
            try TeachPolicy.validate(decoded)
            targets = decoded
        } catch {
            loadError = "Saved Tinycast targets could not be read. The file has been left untouched."
        }
    }

    func target(entryID: String) -> TaughtTarget? { targets.first { $0.entryID == entryID } }

    func save(_ target: TaughtTarget) throws {
        var updated = targets.filter { $0.id != target.id }
        updated.append(target)
        try replace(updated)
    }

    func remove(id: UUID) throws { try replace(targets.filter { $0.id != id }) }

    func replace(_ targets: [TaughtTarget]) throws {
        guard loadError == nil else { throw CocoaError(.fileReadCorruptFile) }
        try TeachPolicy.validate(targets)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(targets)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writePrivate(data)
        self.targets = targets
        revision &+= 1
        onChange?()
    }

    /// The staging inode is private from creation, and rename is the only commit point.
    private func writePrivate(_ data: Data) throws {
        let staging = fileURL.deletingLastPathComponent().appendingPathComponent(".teach-\(UUID()).tmp")
        let descriptor = open(staging.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { try? FileManager.default.removeItem(at: staging) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try file.write(contentsOf: data)
        try file.synchronize()
        try file.close()
        guard rename(staging.path, fileURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
