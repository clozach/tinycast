import Foundation

enum ObsidianEditorScript {
    struct Snapshot: Codable, Sendable {
        let vault: String
        let path: String
        let leaf: String
        let text: String
        let from: Int
        let to: Int

        var selection: NSRange { NSRange(location: from, length: to - from) }
    }

    static let capture = #"""
        (() => {
          const view = app.workspace.activeEditor, editor = view?.editor;
          const active = document.activeElement;
          if (!editor || !view.file || !editor.cm?.contentDOM?.contains(active) ||
              editor.listSelections().length !== 1) throw Error('No focused Markdown editor');
          const text = editor.getValue();
          if (text.length > 1000000) throw Error('Document too large');
          return JSON.stringify({vault: app.appId, path: view.file.path,
            leaf: app.workspace.activeLeaf.id, text,
            from: editor.posToOffset(editor.getCursor('from')),
            to: editor.posToOffset(editor.getCursor('to'))});
        })()
        """#

    static func apply(payloadPath: String) throws -> String {
        guard let path = String(bytes: try JSONEncoder().encode(payloadPath), encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return #"""
            (() => {
              const p = JSON.parse(require('fs').readFileSync(\#(path), 'utf8'));
              const s = p.snapshot, view = app.workspace.activeEditor, editor = view?.editor;
              if (!document.hasFocus() || !editor || app.appId !== s.vault || view.file?.path !== s.path ||
                  app.workspace.activeLeaf.id !== s.leaf || !editor.cm?.contentDOM?.contains(document.activeElement) ||
                  editor.listSelections().length !== 1 || editor.getValue() !== s.text ||
                  editor.posToOffset(editor.getCursor('from')) !== s.from ||
                  editor.posToOffset(editor.getCursor('to')) !== s.to) throw Error('Editor changed');
              editor.transaction({changes: [{from: {line: 0, ch: 0},
                to: editor.offsetToPos(s.text.length), text: p.replacement}]}, 'tinycast-footnote');
              if (editor.getValue() !== p.replacement) throw Error('Edit not confirmed');
              return JSON.stringify({changed: true});
            })()
            """#
    }
}
