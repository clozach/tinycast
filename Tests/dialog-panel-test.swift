import AppKit
import Carbon.HIToolbox

@main
@MainActor
struct DialogPanelTests {
    private static var checks = 0

    static func main() {
        _ = NSApplication.shared
        let editor = NSTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        editor.isEditable = true
        editor.allowsUndo = true
        let panel = DialogPanel(content: editor, cornerRadius: 8)
        panel.allowsMultilineEditing = true
        check(panel.makeFirstResponder(editor), "target accepts focus")
        var confirmed = 0
        panel.onKey = { if case .confirm = $0 { confirmed += 1 } }
        editor.string = "line one"
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        panel.sendEvent(event(kVK_Return, "\r"))
        check(confirmed == 0 && editor.string == "line one\n", "Target Return inserts a newline")
        panel.sendEvent(event(kVK_Return, "\r", modifiers: .command))
        check(confirmed == 1, "Command-Return saves from Target")

        editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: editor.selectedRange())
        panel.sendEvent(event(kVK_Return, "\r"))
        check(confirmed == 1, "IME Return does not save a partial composition")
        editor.unmarkText()
        editor.isFieldEditor = true
        panel.sendEvent(event(kVK_Return, "\r"))
        check(confirmed == 2, "Trigger Return saves")
        editor.isFieldEditor = false
        panel.allowsMultilineEditing = false
        panel.sendEvent(event(kVK_Return, "\r"))
        check(confirmed == 3, "existing dialog Return behavior is preserved")

        editor.string = "literal 🐙 {clipboard}"
        editor.allowsUndo = true
        editor.undoManager?.removeAllActions()
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        check(panel.performKeyEquivalent(with: event(kVK_ANSI_A, "a", modifiers: .command)), "Command-A handled")
        check(editor.selectedRange().length == (editor.string as NSString).length, "entire Unicode target selected")
        editor.insertText("after", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        _ = panel.performKeyEquivalent(with: event(kVK_ANSI_Z, "z", modifiers: .command))
        check(editor.string == "literal 🐙 {clipboard}", "target edit can be undone")
        _ = panel.performKeyEquivalent(with: event(kVK_ANSI_Z, "z", modifiers: [.command, .shift]))
        check(editor.string == "after", "target edit can be redone")
        check(
            (panel.fieldEditor(true, for: NSTextField()) as? NSTextView)?.allowsUndo == true,
            "Trigger field editor supports Undo")
        initialFocus()
        print("\(checks) dialog panel checks passed")
    }

    private static func initialFocus() {
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 150))
        let label = NSTextField(labelWithString: "Trigger")
        let disabled = NSTextField(string: "disabled")
        disabled.isEnabled = false
        let trigger = NSTextField(string: "")
        trigger.frame = CGRect(x: 10, y: 70, width: 200, height: 24)
        let cancel = NSButton(title: "Cancel", target: nil, action: nil)
        for view in [label, disabled, trigger, cancel] { content.addSubview(view) }
        let panel = DialogPanel(content: content, cornerRadius: 8)
        _ = panel.makeFirstResponder(cancel)
        panel.focusFirstTextField()
        check(trigger.currentEditor() === panel.firstResponder, "post-key focus selects the first enabled editable field")
    }

    private static func event(_ code: Int, _ text: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: false, keyCode: UInt16(code))!
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        guard condition() else { fatalError(label) }
    }
}
