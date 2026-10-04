import Foundation

@MainActor
enum ExtensionSendToTests {
    static func run() async {
        let (runtime, host, recorder) = ExtensionTests.makeRuntime()
        defer { runtime.shutdown() }
        do {
            try await runtime.boot(config: .current(supportDirectory: FileManager.default.temporaryDirectory))
        } catch {
            return ExtensionTests.check("Send to runtime boots", false, String(describing: error))
        }
        let code = """
            const React = require("react");
            const { List, ActionPanel, Action } = require("@raycast/api");
            const h = React.createElement;
            const row = (title, action) => h(List.Item, { title, actions: h(ActionPanel, null, action) });
            module.exports.default = function Command() {
              return h(List, null,
                row("Glyph", h(Action.CopyToClipboard, { content: "✦ Send me" })),
                row("File", h(Action.CopyToClipboard, { content: { file: "/tmp/send-to.pdf" } })),
                row("Secret", h(Action.CopyToClipboard, { content: "concealed", concealed: true })),
                row("Browser", h(Action.OpenInBrowser, { url: "https://example.com/path" })),
                row("Open file", h(Action.Open, { target: "/tmp/send-to.txt" })),
                row("Number", h(Action.Paste, { content: 42 })),
                row("Executable", h(Action, { title: "Run", onAction: () => {} })),
                h(List.Item, { title: "Details", detail: h(List.Item.Detail, { markdown: "# Detail body" }) })
              );
            };
            """
        await runtime.start(
            session: "send-to", code: code, file: URL(fileURLWithPath: "/tmp/send-to.js"),
            mode: .view, context: ExtensionTests.launchContext())
        await ExtensionTests.settle()
        guard let tree = recorder.trees.last else {
            ExtensionTests.check("Send to fixture renders", false, recorder.failures.joined())
            return
        }
        let screen = ExtensionScreen(tree: tree, query: "")
        let calls = host.calls
        expectText("extension copy exposes exact content", screen, 0, "✦ Send me")
        expectFile("extension file copy stays a file", screen, 1, "/tmp/send-to.pdf")
        ExtensionTests.check(
            "concealed extension content is not exposed",
            ExtensionSendTo.payload(in: screen, at: 2) == nil)
        expectText("extension URL is preserved", screen, 3, "https://example.com/path")
        expectFile("extension Open preserves file semantics", screen, 4, "/tmp/send-to.txt")
        expectText("extension numeric content is printable", screen, 5, "42")
        ExtensionTests.check(
            "arbitrary actions are not executed to obtain content",
            ExtensionSendTo.payload(in: screen, at: 6) == nil)
        expectText("list detail supplies its displayed markdown", screen, 7, "# Detail body")
        ExtensionTests.check("payload extraction makes no host call", host.calls == calls)
        ExtensionTests.check(
            "opening the source never copies, pastes or opens",
            !host.calls.contains { $0.hasPrefix("clipboard.") || $0.hasPrefix("system.") })
        let filtered = ExtensionScreen(tree: tree, query: "Browser")
        expectText("filtered selection uses visible rows", filtered, 0, "https://example.com/path")
        ExtensionTests.check(
            "a missing result has no payload", ExtensionSendTo.payload(in: filtered, at: 3) == nil)
        await runtime.stop(session: "send-to")
        detailChecks()
    }

    private static func detailChecks() {
        let root = RenderNode(id: 1, type: "Detail", props: ["markdown": .string("A whole **page**")])
        let tree = RenderTree(screens: [RenderNode(id: 2, type: "__screen", children: [root])])
        expectText("rowless Detail supplies markdown", ExtensionScreen(tree: tree, query: ""), 0, "A whole **page**")
        ExtensionTests.check(
            "HTML-only content is not guessed as text",
            ExtensionSendTo.payload(.object(["html": .string("<b>value</b>")])) == nil)
        ExtensionTests.check(
            "empty content has no payload", ExtensionSendTo.payload(.string("")) == nil)
        ExtensionTests.check(
            "non-file URLs cannot masquerade as files",
            ExtensionSendTo.payload(.object(["file": .string("https://example.com/image.png")])) == nil)
    }

    private static func expectText(_ label: String, _ screen: ExtensionScreen, _ index: Int, _ text: String) {
        guard case .text(let actual) = ExtensionSendTo.payload(in: screen, at: index) else {
            return ExtensionTests.check(label, false, "Expected text payload")
        }
        ExtensionTests.check(label, actual == text, actual)
    }

    private static func expectFile(_ label: String, _ screen: ExtensionScreen, _ index: Int, _ path: String) {
        guard case .files(let urls) = ExtensionSendTo.payload(in: screen, at: index) else {
            return ExtensionTests.check(label, false, "Expected file payload")
        }
        ExtensionTests.check(label, urls == [URL(fileURLWithPath: path)])
    }
}
