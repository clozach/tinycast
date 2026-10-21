import Foundation
import JavaScriptCore

@main @MainActor
struct ObsidianEditorScriptTest {
    static var checks = 0
    static var failed = 0

    static func main() throws {
        let context = JSContext()!
        context.evaluateScript(#"""
            var document = {activeElement: {}, hasFocus: () => true};
            var current = 'Some (aside) text', from = 6, to = 11, selections = 1, focus = true, transactions = 0;
            var editor = {
              cm: {contentDOM: {contains: () => focus}}, listSelections: () => Array(selections).fill({}),
              getValue: () => current, getCursor: which => which === 'from' ? from : to,
              posToOffset: n => n, offsetToPos: n => ({line: 0, ch: n}),
              transaction: (tx, origin) => {
                if (tx.changes[0].from.line !== 0 || tx.changes[0].to.ch !== current.length ||
                    origin !== 'tinycast-footnote') throw Error('wrong transaction');
                transactions++; current = tx.changes[0].text;
              }
            };
            var app = {appId: 'vault-id', workspace: {activeLeaf: {id: 'leaf'},
              activeEditor: {file: {path: 'note.md'}, editor}}};
            var payload;
            var require = () => ({readFileSync: () => JSON.stringify(payload)});
            """#)
        let capture = context.evaluateScript(ObsidianEditorScript.capture)!.toString()!
        let snapshot = try JSONDecoder().decode(ObsidianEditorScript.Snapshot.self, from: Data(capture.utf8))
        check("capture includes full buffer and selection", snapshot.text == "Some (aside) text"
            && snapshot.selection == NSRange(location: 6, length: 5) && snapshot.vault == "vault-id")
        context.evaluateScript("payload = {snapshot: \(capture), replacement: 'Changed'}")
        let script = try ObsidianEditorScript.apply(payloadPath: "/tmp/quotes'\"\\\n.json")
        check("apply performs one confirmed transaction", context.evaluateScript(script)?.toString() == "{\"changed\":true}"
            && context.evaluateScript("transactions")?.toInt32() == 1)
        let mutations = [
            "current = 'User typed'", "from = 0", "to = 12", "selections = 2", "focus = false",
            "app.appId = 'other'", "app.workspace.activeLeaf.id = 'other'",
            "app.workspace.activeEditor.file.path = 'other.md'", "document.hasFocus = () => false"
        ]
        for mutation in mutations {
            context.evaluateScript("""
                current = 'Some (aside) text'; from = 6; to = 11; selections = 1; focus = true;
                app.appId = 'vault-id'; app.workspace.activeLeaf.id = 'leaf';
                app.workspace.activeEditor.file.path = 'note.md'; document.hasFocus = () => true;
                \(mutation);
                """)
            context.exception = nil
            _ = context.evaluateScript(script)
            check("changed destination refused: \(mutation)", context.exception != nil
                && context.evaluateScript("transactions")?.toInt32() == 1)
        }
        for mutation in ["focus = false", "selections = 2", "current = 'x'.repeat(1000001)"] {
            context.evaluateScript("focus = true; selections = 1; current = 'Short'; \(mutation)")
            context.exception = nil
            _ = context.evaluateScript(ObsidianEditorScript.capture)
            check("unsafe capture refused: \(mutation)", context.exception != nil)
        }
        print("\(checks - failed)/\(checks) Obsidian editor checks passed")
        if failed > 0 { exit(1) }
    }

    static func check(_ name: String, _ okay: Bool) {
        checks += 1
        if !okay { failed += 1; print("FAIL \(name)") }
    }
}
