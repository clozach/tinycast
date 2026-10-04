import AppKit

final class SendToPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        level = .palette
        isFloatingPanel = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        let editor = super.fieldEditor(createFlag, for: object)
        (editor as? NSTextView)?.allowsUndo = true
        return editor
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
            (firstResponder as? NSTextView)?.hasMarkedText() != true,
            onKeyDown?(event) == true
        { return }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let editor = firstResponder as? NSTextView else {
            return super.performKeyEquivalent(with: event)
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == [.command, .shift], key == "z" {
            editor.undoManager?.redo()
            return true
        }
        guard modifiers == .command else { return super.performKeyEquivalent(with: event) }
        switch key {
        case "a": editor.selectAll(nil)
        case "c": editor.copy(nil)
        case "x": editor.cut(nil)
        case "v": editor.paste(nil)
        case "z": editor.undoManager?.undo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
