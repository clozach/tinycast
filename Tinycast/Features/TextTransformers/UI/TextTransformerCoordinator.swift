import AppKit

@MainActor
final class TextTransformerCoordinator {
    private unowned let core: AppCore
    private var isTransforming = false

    init(core: AppCore) { self.core = core }

    func extractFootnote() {
        guard !isTransforming else { return }
        guard Permissions.ensureAccessibility(),
            let app = core.paletteCoordinator.targetApp,
            app.processIdentifier != NSRunningApplication.current.processIdentifier,
            let buffer = EditableTextBuffer.capture(in: app)
        else {
            core.showMessage(
                String(localized: "This editor does not expose its complete text buffer. No text was changed."),
                tone: .danger)
            return
        }
        let transformed: String
        do {
            transformed = try FootnoteTransformer.transform(buffer.text, selection: buffer.selection)
        } catch {
            core.showMessage(
                String(localized: "Select an aside inside balanced parentheses in a document with valid Markdown footnotes."),
                tone: .danger)
            return
        }
        isTransforming = true
        core.paletteCoordinator.hidePalette()
        core.textInjector.replaceBuffer(
            buffer, with: transformed,
            onDelivered: { [weak self] in
                self?.isTransforming = false
                self?.core.showMessage(String(localized: "Footnote added. Press ⌘Z in your editor to undo."))
            },
            onFailed: { [weak self] in
                self?.isTransforming = false
                self?.core.showMessage(
                    String(
                        localized: "The edit could not be confirmed. Check your editor before trying again; ⌘Z undoes a paste."),
                    tone: .danger)
            })
    }
}
