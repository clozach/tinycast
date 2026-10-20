import Foundation

@main
@MainActor
struct TeachTests {
    private static var checks = 0

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        policy()
        try persistence(in: directory)
        try rejectedWrites(in: directory)
        print("\(checks) Teach checks passed")
    }

    private static func policy() {
        check(TeachPolicy.trigger(" \tDARK\n") == "DARK", "trigger edges are trimmed")
        check(
            TeachPolicy.conflict(" Dark ", aliases: ["appearance": "ＤＡＲＫ"], excluding: nil) == "appearance",
            "case and width collide independently of the entry title")
        check(
            TeachPolicy.conflict("dark", aliases: ["appearance": "DARK"], excluding: "appearance") == nil,
            "editing one's own alias is allowed")
        check(
            TeachPolicy.conflict("dark", aliases: ["appearance": "light"], excluding: nil) == nil,
            "a distinct trigger stays available")
        for target in ["https://example.com/a?q={literal}", "example.com", "~/Documents", "mailto:hi@example.com"] {
            check(TeachPolicy.openDestination(target) != nil, "recognized open destination")
        }
        for target in ["", "plain text", "https://", "javascript:alert(1)", "data:text/plain,hi", "https://example.com\nextra"] {
            check(TeachPolicy.openDestination(target) == nil, "invalid or executable text is not Open")
        }
    }

    private static func persistence(in directory: URL) throws {
        let url = directory.appendingPathComponent("targets.json")
        let store = TeachStore(fileURL: url)
        var changes = 0
        store.onChange = { changes += 1 }
        let literal = " \t{clipboard}\n{argument name=\"Untouched\"}\r\n🐙 café \\ $HOME `echo no`  "
        let id = UUID()
        let target = TaughtTarget(id: id, name: "payload", text: literal, delivery: .paste)
        try store.save(target)
        check(store.target(entryID: target.entryID) == target, "stable entry ID resolves immediately")
        check(TeachStore(fileURL: url).targets == [target], "literal text round-trips byte-for-byte")
        let legacy = Data("""
            {"id":"\(id.uuidString)","name":"gal","text":"http://t.local:5194","delivery":{"open":{}}}
            """.utf8)
        let migrated = try JSONDecoder().decode(TaughtTarget.self, from: legacy)
        check(migrated.title == nil && migrated.displayTitle == "gal", "old library keeps its trigger as title")
        var titled = migrated
        titled.title = "Service Gallery"
        check(titled.displayTitle == "Service Gallery" && titled.name == "gal", "title does not replace trigger")
        check(titled.id == id && titled.text == migrated.text && titled.delivery == migrated.delivery,
            "title changes preserve identity, payload and delivery")
        check(titled.targetPreview == "http://t.local:5194", "Open shows its destination")
        check(target.targetPreview.contains("{clipboard}") && !target.targetPreview.contains("\n"),
            "Paste preview is concise while stored text stays literal")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        check(permissions?.intValue == 0o600, "stored payload file is owner-only")
        let updated = TaughtTarget(
            id: id, name: "web", text: "https://example.com", delivery: .open(application: "com.apple.Safari"))
        try store.save(updated)
        check(store.targets == [updated], "editing replaces the same ID without duplicates")
        check(TeachStore(fileURL: url).targets == [updated], "browser choice survives reload")
        try store.remove(id: id)
        check(TeachStore(fileURL: url).targets.isEmpty, "deletion persists")
        check(changes == 3, "only committed mutations publish")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        check(!files.contains(where: { $0.hasSuffix(".tmp") }), "staging files do not linger")
    }

    private static func rejectedWrites(in directory: URL) throws {
        let url = directory.appendingPathComponent("guarded.json")
        let store = TeachStore(fileURL: url)
        let original = TaughtTarget(id: UUID(), name: "original", text: "literal", delivery: .paste)
        try store.save(original)
        let originalBytes = try Data(contentsOf: url)
        for invalid in [
            [original, original],
            [TaughtTarget(id: UUID(), name: "bad", text: "not a URL", delivery: .open(application: nil))],
            [TaughtTarget(id: UUID(), name: "two\nlines", text: "literal", delivery: .paste)]
        ] {
            do {
                try store.replace(invalid)
                check(false, "invalid import must fail")
            } catch {
                check(true, "invalid import rejected")
            }
            check(store.targets == [original], "failed import leaves memory unchanged")
            try check(try Data(contentsOf: url) == originalBytes, "failed import leaves disk unchanged")
        }

        let corruptURL = directory.appendingPathComponent("corrupt.json")
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: corruptURL)
        let unreadable = TeachStore(fileURL: corruptURL)
        check(unreadable.loadError != nil, "corrupt source is reported")
        do {
            try unreadable.save(original)
            check(false, "must not overwrite corrupt source")
        } catch {
            try check(try Data(contentsOf: corruptURL) == corrupt, "corrupt source is preserved")
        }

        let failedURL = directory.appendingPathComponent("destination")
        let failed = TeachStore(fileURL: failedURL)
        try FileManager.default.createDirectory(at: failedURL, withIntermediateDirectories: false)
        do {
            try failed.save(original)
            check(false, "rename over a directory must fail")
        } catch {
            check(failed.targets.isEmpty, "failed disk commit leaves memory unchanged")
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        check(!files.contains(where: { $0.hasSuffix(".tmp") }), "failed writes remove their staging file")
    }

    private static func check(_ condition: @autoclosure () throws -> Bool, _ label: String) rethrows {
        checks += 1
        guard try condition() else { fatalError(label) }
    }
}
