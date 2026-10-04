import AppKit
import Carbon.HIToolbox

@main
@MainActor
struct SendToPanelTests {
    private static var checks = 0

    static func main() {
        _ = NSApplication.shared
        let panel = SendToPanel()
        panel.setContentSize(CGSize(width: 300, height: 100))
        let editor = NSTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        editor.isEditable = true
        editor.allowsUndo = true
        panel.contentView = editor
        check(panel.makeFirstResponder(editor), "search editor accepts focus")
        selectAll(panel: panel, editor: editor)
        undoRedo(panel: panel, editor: editor)
        composition(panel: panel, editor: editor)
        check(
            (panel.fieldEditor(true, for: NSTextField()) as? NSTextView)?.allowsUndo == true,
            "the shared search field editor enables undo")
        print("\(checks) Send to panel checks passed")
    }

    private static func selectAll(panel: SendToPanel, editor: NSTextView) {
        editor.string = "Send 🎉 to another app"
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        check(panel.performKeyEquivalent(with: event(kVK_ANSI_A, "a", modifiers: .command)), "⌘A handled")
        check(
            editor.selectedRange() == NSRange(location: 0, length: (editor.string as NSString).length),
            "⌘A selects the entire Unicode query")
    }

    private static func undoRedo(panel: SendToPanel, editor: NSTextView) {
        editor.string = "before"
        editor.setSelectedRange(NSRange(location: 0, length: 6))
        editor.insertText("after", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        check(editor.string == "after" && editor.undoManager?.canUndo == true, "editing registers undo")
        check(panel.performKeyEquivalent(with: event(kVK_ANSI_Z, "z", modifiers: .command)), "⌘Z handled")
        check(editor.string == "before", "⌘Z restores the query")
        check(
            panel.performKeyEquivalent(with: event(kVK_ANSI_Z, "z", modifiers: [.command, .shift])),
            "⇧⌘Z handled")
        check(editor.string == "after", "⇧⌘Z restores the edit")
    }

    private static func composition(panel: SendToPanel, editor: NSTextView) {
        var navigations = 0
        panel.onKeyDown = { _ in navigations += 1; return true }
        let keys = [
            (kVK_Return, "\r"), (kVK_UpArrow, "\u{f700}"),
            (kVK_DownArrow, "\u{f701}"), (kVK_LeftArrow, "\u{f702}"),
            (kVK_RightArrow, "\u{f703}"), (kVK_Escape, "\u{1b}")
        ]
        for (code, characters) in keys {
            editor.string = ""
            editor.setMarkedText(
                "に", selectedRange: NSRange(location: 1, length: 0),
                replacementRange: NSRange(location: 0, length: 0))
            check(editor.hasMarkedText(), "IME fixture has marked text for key \(code)")
            panel.sendEvent(event(code, characters))
            check(navigations == 0, "composition key \(code) never navigates or sends")
            editor.unmarkText()
        }
        panel.sendEvent(event(kVK_Return, "\r"))
        check(navigations == 1, "Return reaches the chooser after composition ends")
    }

    private static func event(
        _ code: Int, _ characters: String, modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code))!
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        guard condition() else { fatalError(label) }
    }
}
