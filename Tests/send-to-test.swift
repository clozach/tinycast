import AppKit

@MainActor
enum Paster {
    static func postCommandV(toPid: Int32?) { fatalError("Tests must inject paste delivery") }
}

enum Permissions {
    static func ensureAccessibility() -> Bool { fatalError("Tests must inject permission checks") }
}

@main
struct SendToTest {
    @MainActor static var checks = 0

    @MainActor
    static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        guard condition() else { fatalError(label) }
    }

    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("send-to-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let first = root.appendingPathComponent("first.txt")
        let second = root.appendingPathComponent("second.txt")
        try Data("First".utf8).write(to: first)
        try Data("Second".utf8).write(to: second)
        try targets(first: first, second: second)
        try targetIdentities(first: first, second: second)
        try snapshots(board: board, root: root, first: first, second: second)
        try await delivery(board: board, file: first)
        print("\(checks) Send to checks passed")
    }

    @MainActor
    static func targets(first: URL, second: URL) throws {
        let editor = URL(fileURLWithPath: "/Applications/Editor.app")
        let duplicate = URL(fileURLWithPath: "/Applications/./Editor.app")
        let otherEditor = URL(fileURLWithPath: "/elsewhere/Editor.app")
        let preferred = URL(fileURLWithPath: "/Applications/Preferred.app")
        let unsupported = URL(fileURLWithPath: "/Applications/FirstOnly.app")
        var sources = SendToService.Sources()
        sources.openers = {
            $0 == first ? [editor, duplicate, otherEditor, unsupported, preferred] : [preferred, editor, otherEditor]
        }
        sources.defaultOpener = { _ in preferred }
        sources.appIdentity = { _ in nil }
        sources.ownPID = 100
        sources.running = { [
            .init(pid: 200, name: "Frontmost", url: editor),
            .init(pid: 100, name: "Tinycast", url: nil),
            .init(pid: 201, name: "Behind", url: nil),
            .init(pid: 200, name: "Duplicate", url: editor)
        ] }
        let found = try SendToService.targets(for: .files([first, second]), sources: sources)
        check(found.count == 5, "intersection, self exclusion and duplicate removal")
        check(found[0] == .open(app: preferred, items: [first, second]), "default opens first")
        check(found[1] == .open(app: editor, items: [first, second]), "ordered compatible app")
        check(found[2].appURL == otherEditor, "distinct bundles may share a filename")
        check(found[3] == .paste(pid: 200, name: "Frontmost", app: editor), "running order preserved")
        check(found[4].name == "Behind", "running app without bundle URL remains usable")
        check(Set(found.map(\.id)).count == found.count, "target IDs are distinct")
        let textTargets = try SendToService.targets(for: .text("Some plain text"), sources: sources)
        check(textTargets.count == 2 && textTargets.allSatisfy { !$0.isOpen }, "plain text is paste-only")
        check(SendToPayload.text("  https://example.com/a  ").openItems.count == 1, "web link opens")
        check(SendToPayload.text("mailto:al@example.com").openItems.count == 1, "deep link opens")
        check(SendToPayload.text("a: value").openItems.isEmpty, "prose colon is not a URL")
        check(SendToPayload.text("https:").openItems.isEmpty, "URL needs a host")
        check(SendToPayload.text("  Hello\nworld  ").displayTitle == "Hello", "title takes first line")
        check(SendToPayload.files([first, second]).displayTitle == "2 files", "file count title")
        do {
            _ = try SendToService.targets(for: .files([]), sources: sources)
            fatalError("Empty file list accepted")
        } catch SendToError.emptyPayload { checks += 1 }
        do {
            _ = try SendToService.targets(for: .text(""), sources: sources)
            fatalError("Empty text accepted")
        } catch SendToError.emptyPayload { checks += 1 }
    }

    @MainActor
    static func targetIdentities(first: URL, second: URL) throws {
        let old = URL(fileURLWithPath: "/Old/Browser.app")
        let preferred = URL(fileURLWithPath: "/Preferred/Browser.app")
        let other = URL(fileURLWithPath: "/Other/Browser.app")
        let unsupported = URL(fileURLWithPath: "/Unsupported/Browser.app")
        let unknown = URL(fileURLWithPath: "/Unknown/Browser.app")
        let secondUnknown = URL(fileURLWithPath: "/SecondUnknown/Browser.app")
        let identities = [old: "example.browser", preferred: "example.browser", other: "example.other",
                          unsupported: "example.browser", secondUnknown: ""]
        var sources = SendToService.Sources()
        sources.openers = { url in
            let compatible = [old, preferred, other, unknown, secondUnknown]
            return url == first ? [unsupported] + compatible : compatible
        }
        sources.defaultOpener = { _ in preferred }
        sources.appIdentity = { identities[$0] }
        sources.running = { [] }
        let targets = try SendToService.targets(for: .files([first, second]), sources: sources)
        check(targets.map(\.appURL) == [preferred, other, unknown, secondUnknown], "bundle identity collapses copies")
        check(targets.first?.appURL == preferred, "preferred installation survives deduplication")
        check(targets.contains { $0.appURL == other }, "same name with different bundle ID remains")
        check(targets.contains { $0.appURL == unknown }, "missing bundle ID falls back to path")
        check(targets.contains { $0.appURL == secondUnknown }, "empty bundle ID falls back to path")
        sources.defaultOpener = { _ in unsupported }
        let noUnsupported = try SendToService.targets(for: .files([first, second]), sources: sources)
        check(noUnsupported.first?.appURL == old, "incompatible default never displaces a compatible installation")
        check(!noUnsupported.contains { $0.appURL == unsupported }, "intersection precedes identity deduplication")
    }

    @MainActor
    static func snapshots(board: NSPasteboard, root: URL, first: URL, second: URL) throws {
        board.clearContents()
        let empty = try SendToService.snapshot(from: board)
        check(empty == nil, "empty clipboard has no payload")
        let rich = NSPasteboardItem()
        rich.setString("original", forType: .string)
        let richData = Data("{\\rtf1 original}".utf8)
        rich.setData(richData, forType: .rtf)
        check(board.writeObjects([rich]), "fixture writes to named board")
        guard let frozen = try SendToService.snapshot(from: board) else { fatalError("Snapshot missing") }
        board.clearContents()
        board.setString("replacement", forType: .string)
        try SendToService.write(frozen, to: board)
        check(board.string(forType: .string) == "original", "clipboard is frozen before chooser opens")
        check(board.data(forType: .rtf) == richData, "rich representations survive")
        check(board.data(forType: .init("com.tinycast.internal")) != nil, "paste write prevents recapture")
        try SendToService.write(.files([first, second]), to: board)
        check(board.pasteboardItems?.count == 2, "multiple files stay separate")
        check(board.pasteboardItems?.first?.string(forType: .string) == first.path, "file text is its path")
        guard let files = try SendToService.snapshot(from: board) else { fatalError("Files missing") }
        check(files.openItems == [first, second], "file snapshot retains ordered URLs")
        try SendToService.write(files, to: board)
        check(board.pasteboardItems?.count == 2, "file snapshot replays every item")
        board.clearContents()
        board.setString("https://example.com", forType: .string)
        let link = try SendToService.snapshot(from: board)
        check(link?.openItems.first?.absoluteString == "https://example.com", "clipboard link can open in an app")
        board.clearContents()
        let encodedPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        let png = Data(base64Encoded: encodedPNG)!
        board.setData(png, forType: .png)
        guard let image = try SendToService.snapshot(from: board, stagingDirectory: root),
              let imageURL = image.openItems.first else { fatalError("Image missing") }
        let imageData = try Data(contentsOf: imageURL)
        check(imageData == png, "image opener receives frozen bytes")
        board.clearContents()
        board.setString("clipboard changed", forType: .string)
        try SendToService.write(image, to: board)
        check(board.data(forType: .png) == png, "image paste receives frozen bytes")
        try SendToService.write(.image(imageURL), to: board)
        check(board.data(forType: .png) == png, "image payload preserves image type")
        let before = board.changeCount
        do {
            try SendToService.write(.files([root.appendingPathComponent("gone")]), to: board)
            fatalError("Vanished file accepted")
        } catch SendToError.unavailableFile { checks += 1 }
        check(board.changeCount == before, "vanished file leaves clipboard unchanged")
        let oldDirectory = root.appendingPathComponent(String(repeating: "a", count: 64))
        let recentDirectory = root.appendingPathComponent(String(repeating: "b", count: 64))
        let untouchedDirectory = root.appendingPathComponent("unrelated")
        let now = Date()
        for directory in [oldDirectory, recentDirectory, untouchedDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for directory in [oldDirectory, untouchedDirectory] {
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-90_000)], ofItemAtPath: directory.path)
        }
        try SendToService.removeExpiredImages(in: root, now: now)
        check(!FileManager.default.fileExists(atPath: oldDirectory.path), "expired staged image directory is removed")
        check(FileManager.default.fileExists(atPath: recentDirectory.path), "recent image survives recipient reads")
        check(FileManager.default.fileExists(atPath: untouchedDirectory.path), "cleanup ignores unrelated names")
    }

    @MainActor
    static func delivery(board: NSPasteboard, file: URL) async throws {
        let target = SendToTarget.paste(pid: 200, name: "Editor", app: nil)
        var front: Int32? = 100
        var activated: [Int32] = []
        var posted: [Int32] = []
        var sleeps = 0
        var environment = SendToService.Environment()
        environment.pasteboard = board
        environment.canPaste = { true }
        environment.activate = { activated.append($0); return true }
        environment.frontmost = { front }
        environment.postPaste = { posted.append($0) }
        environment.sleep = { _ in sleeps += 1; if sleeps == 2 { front = 200 } }
        environment.open = { _, _ in fatalError("Paste must not open an app") }
        try await SendToService.send(.text("payload"), to: target, environment: environment)
        check(activated == [200], "activates selected app exactly once")
        check(posted == [200], "paste goes only to chosen PID")
        check(board.string(forType: .string) == "payload", "paste uses chosen payload")
        check(sleeps == 3, "waits for activation and then settles")
        environment.sleep = { _ in
            board.clearContents()
            board.setString("different clipboard", forType: .string)
        }
        try await SendToService.send(.text("chosen content"), to: target, environment: environment)
        check(board.string(forType: .string) == "chosen content", "clipboard changes during activation cannot change payload")
        front = 100
        posted = []
        sleeps = 0
        environment.sleep = { _ in sleeps += 1 }
        do {
            try await SendToService.send(.text("timeout"), to: target, environment: environment)
            fatalError("Activation timeout accepted")
        } catch SendToError.activationTimedOut { checks += 1 }
        check(posted.isEmpty && sleeps == 38, "timeout is bounded and posts nothing")
        check(board.string(forType: .string) == "timeout", "failed activation leaves item available to paste")
        front = 200
        sleeps = 0
        environment.sleep = { _ in sleeps += 1; front = 100 }
        do {
            try await SendToService.send(.text("focus changed"), to: target, environment: environment)
            fatalError("Focus race accepted")
        } catch SendToError.activationTimedOut { checks += 1 }
        check(posted.isEmpty, "losing focus during settle never pastes into another app")
        let beforeDenied = board.changeCount
        environment.canPaste = { false }
        do {
            try await SendToService.send(.text("denied"), to: target, environment: environment)
            fatalError("Permission denial accepted")
        } catch SendToError.accessibility { checks += 1 }
        check(board.changeCount == beforeDenied, "permission denial keeps clipboard unchanged")
        environment.canPaste = { true }
        environment.activate = { _ in false }
        do {
            try await SendToService.send(.text("app quit"), to: target, environment: environment)
            fatalError("Unavailable app accepted")
        } catch SendToError.appUnavailable { checks += 1 }
        check(posted.isEmpty, "unavailable app receives nothing")
        let app = URL(fileURLWithPath: "/Applications/Chosen.app")
        var opened: [URL] = []
        var openedApp: URL?
        environment.open = { opened = $0; openedApp = $1 }
        let beforeOpen = board.changeCount
        try await SendToService.send(.files([file]), to: .open(app: app, items: [file]), environment: environment)
        check(opened == [file] && openedApp == app, "Open in receives exact chosen app and items")
        check(board.changeCount == beforeOpen, "Open in does not change clipboard")
        environment.open = { _, _ in throw SendToError.appUnavailable("Chosen") }
        do {
            try await SendToService.send(.files([file]), to: .open(app: app, items: [file]), environment: environment)
            fatalError("Open failure swallowed")
        } catch SendToError.appUnavailable { checks += 1 }
        environment.activate = { _ in true }
        environment.sleep = { _ in throw CancellationError() }
        do {
            try await SendToService.send(.text("cancel"), to: target, environment: environment)
            fatalError("Cancellation swallowed")
        } catch is CancellationError { checks += 1 }
        check(posted.isEmpty, "cancellation never posts a paste")
    }
}
