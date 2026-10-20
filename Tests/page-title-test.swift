import Foundation
import Network

@main @MainActor
struct PageTitleTests {
    private static var checks = 0

    static func main() async throws {
        parsing()
        try await races()
        try await transport()
        print("\(checks) page title checks passed")
    }

    private static func parsing() {
        check(PageTitle.parse("<TITLE>Service &amp; Gallery &#x1F419;\n Tools</TITLE>") == "Service & Gallery 🐙 Tools",
            "title entities and whitespace become plain text")
        for prefix in ["<!-- ", "<script>var text = '", "<style>/* "] {
            check(PageTitle.parse(prefix + "<title>Fake</title>") == nil, "unfinished inert content has no title")
        }
        check(PageTitle.parse("<!-- <title>Fake</title> --><title>Real</title>") == "Real", "closed comments ignored")
        check(PageTitle.parse("<script>'<title>Fake</title>'</script><title>Real</title>") == "Real", "scripts ignored")
        check(PageTitle.parse("<title>\u{202e}Clean\u{0007}</title>") == "Clean", "controls and bidi overrides removed")
        check(PageTitle.parse(String(repeating: ">", count: PageTitle.maximumBytes)) == nil,
            "bounded adversarial prefix parses once")
        check(PageTitle.parse(String(repeating: "<title ", count: 37_449)) == nil, "malformed opening tags do not backtrack")
        check(PageTitle.parse(String(repeating: "<title>", count: 32_000)) == nil, "missing title close does not backtrack")
        for tag in ["textarea", "xmp", "iframe", "style", "template"] {
            check(PageTitle.parse("<\(tag)><title>Fake</title></\(tag)><title>Real</title>") == "Real",
                "inert element cannot supply a title")
        }
        check(PageTitle.parse("<meta data-example=\"<title>Fake</title>\"><title>Real</title>") == "Real",
            "quoted attribute is not a title element")
        check(PageTitle.parse("<title>" + String(repeating: "a", count: 300) + "</title>")?.count == 240,
            "page title length is bounded")
        for value in ["file:///etc/passwd", "javascript:alert(1)", "https://user:password@example.com", "mailto:a@b.com"] {
            check(PageTitle.url(value) == nil, "only credential-free HTTP(S) fetched")
        }
        check(PageTitle.url("http://t.local:5194") != nil, "user's local web service is eligible")
    }

    private static func races() async throws {
        let gate = TitleGate()
        let loader = TeachTitleLoader(title: nil, fetch: { await gate.fetch($0.path) })
        let old = loader.refresh(target: "https://example.com/old")
        await gate.waitFor("/old")
        let fresh = loader.refresh(target: "https://example.com/new")
        await gate.waitFor("/new")
        await gate.resolve("/old", title: "Old")
        _ = await old?.value
        check(loader.title.isEmpty, "changed URL rejects a late title")
        await gate.resolve("/new", title: "New")
        _ = await fresh?.value
        check(loader.title == "New", "latest URL supplies title")

        let manual = loader.refresh(target: "https://example.com/manual")
        await gate.waitFor("/manual")
        loader.title = "Typed"
        loader.title = ""
        await gate.resolve("/manual", title: "Must not return")
        _ = await manual?.value
        check(loader.title.isEmpty && loader.status == .idle, "typing then clearing title still rejects suggestion")
        check(loader.refresh(target: "https://example.com/again") == nil, "manual title ownership survives target changes")

        let failed = TeachTitleLoader(title: nil, fetch: { _ in nil })
        _ = await failed.refresh(target: "https://example.com")?.value
        check(failed.status == .unavailable && failed.title.isEmpty, "fetch failure leaves form usable")
        let cancelled = TeachTitleLoader(title: nil, fetch: { _ in await gate.fetch("/cancel") })
        let cancellation = cancelled.refresh(target: "https://example.com/cancel")
        await gate.waitFor("/cancel")
        cancelled.cancel()
        await gate.resolve("/cancel", title: "Late")
        _ = await cancellation?.value
        check(cancelled.title.isEmpty, "cancel rejects late completion")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TeachStore(fileURL: directory.appendingPathComponent("targets.json"))
        let target = TaughtTarget(id: UUID(), name: "gal", text: "http://t.local:5194", delivery: .open(application: nil))
        for mode in ["saved", "deleted", "edited", "restored"] {
            let path = "/" + mode
            let saving = TeachTitleLoader(title: nil, fetch: { _ in await gate.fetch(path) })
            saving.refresh(target: "https://example.com" + path)
            await gate.waitFor(path)
            try store.save(target)
            let completion = saving.completeAfterSave(target, store: store)
            if mode == "deleted" || mode == "restored" { try store.remove(id: target.id) }
            if mode == "restored" { try store.save(target) }
            if mode == "edited" {
                var edited = target
                edited.title = "My title"
                try store.save(edited)
            }
            await gate.resolve(path, title: "Service Gallery")
            await completion?.value
            switch mode {
            case "saved": check(store.targets.first?.title == "Service Gallery", "fast Save receives page title")
            case "deleted": check(store.targets.isEmpty, "Undo prevents a late metadata write")
            case "edited": check(store.targets.first?.title == "My title", "later edit wins over metadata")
            default: check(store.targets == [target], "delete/restore of identical data still invalidates stale metadata")
            }
        }
    }

    private static func transport() async throws {
        let server = try await TitleServer()
        defer { server.stop() }
        check(await PageTitleFetcher.fetch(server.url("/html")) == "Service Gallery", "real HTTP title fetched")
        check(await PageTitleFetcher.fetch(server.url("/redirect")) == "Service Gallery", "HTTP redirect followed")
        for path in ["/mime", "/unsafe", "/loop", "/large", "/error"] {
            check(await PageTitleFetcher.fetch(server.url(path)) == nil, "unsafe or invalid HTTP response rejected: \(path)")
        }
    }

    private static func check(_ condition: Bool, _ label: String) {
        checks += 1
        guard condition else { fatalError(label) }
    }
}

private actor TitleGate {
    private var pending: [String: CheckedContinuation<String?, Never>] = [:]
    private var arrivals: [String: CheckedContinuation<Void, Never>] = [:]

    func fetch(_ path: String) async -> String? {
        await withCheckedContinuation { pending[path] = $0; arrivals.removeValue(forKey: path)?.resume() }
    }
    func waitFor(_ path: String) async {
        guard pending[path] == nil else { return }
        await withCheckedContinuation { arrivals[path] = $0 }
    }
    func resolve(_ path: String, title: String?) { pending.removeValue(forKey: path)?.resume(returning: title) }
}

private final class TitleServer: @unchecked Sendable {
    private let listener: NWListener
    private let port: UInt16

    init() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let path = (String(bytes: data ?? Data(), encoding: .utf8) ?? "")
                    .split(separator: " ").dropFirst().first ?? ""
                let response: String
                switch path {
                case "/redirect": response = "HTTP/1.1 302 Found\r\nLocation: /html\r\n"
                case "/unsafe": response = "HTTP/1.1 302 Found\r\nLocation: file:///etc/passwd\r\n"
                case "/loop": response = "HTTP/1.1 302 Found\r\nLocation: /loop\r\n"
                case "/mime": response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n<title>Ignored</title>"
                case "/large":
                    response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n"
                        + String(repeating: ">", count: PageTitle.maximumBytes) + "<title>Too late</title>"
                case "/error": response = "HTTP/1.1 500 Error\r\nContent-Type: text/html\r\n\r\n<title>Error</title>"
                default:
                    response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n\r\n"
                        + "<title>Service Gallery</title>"
                }
                let terminated = response.contains("\r\n\r\n") ? response : response + "\r\n"
                connection.send(content: Data(terminated.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        port = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port!.rawValue)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: .global())
        }
    }

    func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)" + path)! }
    func stop() { listener.cancel() }
}
