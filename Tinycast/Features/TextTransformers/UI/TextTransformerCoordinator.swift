import AppKit

@MainActor
final class TextTransformerCoordinator {
    private unowned let core: AppCore
    private var isTransforming = false

    init(core: AppCore) { self.core = core }

    private enum Operation { case extract, lift }

    func extractFootnote() { apply(.extract) }
    func liftFootnote() { apply(.lift) }

    private func apply(_ operation: Operation) {
        guard !isTransforming else { return }
        guard Permissions.ensureAccessibility(),
            let app = core.paletteCoordinator.targetApp,
            app.processIdentifier != NSRunningApplication.current.processIdentifier
        else {
            core.showMessage(
                String(localized: "This editor does not expose its complete text buffer. No text was changed."),
                tone: .danger)
            return
        }
        if app.bundleIdentifier == "md.obsidian" {
            applyInObsidian(operation, app: app)
            return
        }
        guard let buffer = EditableTextBuffer.capture(in: app) else {
            core.showMessage(
                String(localized: "This editor does not expose its complete text buffer. No text was changed."),
                tone: .danger)
            return
        }
        let transformed: String
        let clipboard: BufferClipboardDisposition
        do {
            switch operation {
            case .extract:
                transformed = try FootnoteTransformer.transform(buffer.text, selection: buffer.selection)
                clipboard = .restore
            case .lift:
                let result = try FootnoteLift.transform(buffer.text, selection: buffer.selection)
                transformed = result.document
                clipboard = .copy(result.clipboard)
            }
        } catch {
            core.showMessage(
                operation == .extract
                    ? String(
                        localized: "Select an aside inside balanced parentheses in a document with valid Markdown footnotes.")
                    : String(
                        localized: """
                        Place the caret inside a footnote reference or its definition in a document with valid Markdown footnotes.
                        """),
                tone: .danger)
            return
        }
        isTransforming = true
        core.paletteCoordinator.hidePalette()
        core.textInjector.replaceBuffer(
            buffer, with: transformed, clipboard: clipboard,
            onDelivered: { [weak self] in
                self?.isTransforming = false
                self?.core.showMessage(
                    operation == .extract
                        ? String(localized: "Footnote added. Press ⌘Z in your editor to undo.")
                        : String(localized: "Footnote lifted to the clipboard. Press ⌘Z in your editor to undo."))
            },
            onFailed: { [weak self] in
                self?.isTransforming = false
                self?.core.showMessage(
                    String(
                        localized: """
                        The edit or clipboard copy could not be confirmed. Check your editor and clipboard before trying again; \
                        ⌘Z undoes a paste.
                        """),
                    tone: .danger)
            })
    }

    private func applyInObsidian(_ operation: Operation, app: NSRunningApplication) {
        guard !core.textInjector.isDelivering else { return }
        isTransforming = true
        Task { [weak self] in
            guard let self else { return }
            defer { isTransforming = false }
            do {
                let buffer = try await ObsidianTextBuffer.capture(in: app)
                let document: String
                let clipboard: BufferClipboardDisposition
                switch operation {
                case .extract:
                    document = try FootnoteTransformer.transform(buffer.snapshot.text, selection: buffer.snapshot.selection)
                    clipboard = .restore
                case .lift:
                    let result = try FootnoteLift.transform(buffer.snapshot.text, selection: buffer.snapshot.selection)
                    document = result.document
                    clipboard = .copy(result.clipboard)
                }
                let originalClipboard = NSPasteboard.general.changeCount
                core.paletteCoordinator.hidePalette()
                try await buffer.replace(with: document)
                if case .copy(let text) = clipboard {
                    guard NSPasteboard.general.changeCount == originalClipboard, Paster.copyPlainText(text) else {
                        throw FootnoteLift.Failure.noFootnote
                    }
                }
                core.showMessage(operation == .extract
                    ? String(localized: "Footnote added. Press ⌘Z in your editor to undo.")
                    : String(localized: "Footnote lifted to the clipboard. Press ⌘Z in your editor to undo."))
            } catch {
                core.showMessage(String(localized: """
                    The edit or clipboard copy could not be confirmed. Check your editor and clipboard before trying again; \
                    ⌘Z undoes a paste.
                    """), tone: .danger)
            }
        }
    }

}
