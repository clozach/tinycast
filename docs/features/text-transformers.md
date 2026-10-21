# Text transformers

## Invariants

- Transform a captured complete text buffer, including its UTF-16 selection. Never treat copied selection text as the document.
- Validate the source element, selection and original text after activation and again immediately before delivery. A changed source cancels delivery.
- Accessibility buffers use one native paste on the existing serialized delivery queue. Obsidian uses one editor transaction. Never delete first or retry an uncertain edit.
- Accessibility delivery borrows the clipboard with the ownership-aware lease. Extraction restores it; lifting commits an ordinary, unmarked clipboard item only after exact document readback. An intervening copy wins.
- Parsing and numbering live in Foundation-only models. `AppCore` owns `TextTransformerCoordinator`; the launcher invokes it through a built-in command.

## Extract Markdown Footnote

Select text inside an aside, or leave the caret inside it. Invoke **Extract Markdown Footnote** from the launcher. Assign an alias or shortcut in **Settings → Commands** if desired; no shortcut is assigned by default.

The transformer chooses the smallest balanced pair of parentheses enclosing the selection, removes its outer parentheses and surrounding internal whitespace, and replaces the aside with a footnote reference. Horizontal space between the preceding word and the aside is removed. Indentation at the start of a line is preserved. It capitalizes the first letter without lowercasing names or acronyms; a code- or URL-led sentence stays verbatim.

```markdown
The idea (a NASA pilot tested it) is promising.

A later claim[^7] already has a note.

[^7]: Existing note.
```

Selecting `NASA pilot` produces:

```markdown
The idea[^1] is promising.

A later claim[^2] already has a note.

[^1]: A NASA pilot tested it

[^2]: Existing note.
```

Each invocation renumbers all recognized references and definitions by first reference in the body. Repeated references share a number. Named labels are converted to numbers, case-insensitively. Unreferenced definitions are preserved after referenced notes in their previous order. All definitions move to the end, with a blank line before them and between notes; multiline continuation text is indented four spaces. Existing LF, CRLF or CR line endings are preserved; mixed endings are refused. Numbering does not run continuously while the user edits elsewhere.

The conservative Markdown scanner ignores escaped punctuation, inline and fenced code (including quoted/list fences), indented code, inline link destinations, reference-link definitions, wiki links, math delimiters, HTML comments/tags/autolinks, and YAML frontmatter. Duplicate definitions, missing definitions, nested footnote references, empty asides, selections spanning separate asides and extraction from a footnote definition are refused. It is a small scanner, not a complete Markdown dialect parser.

## Lift Markdown Footnote

Invoke **Lift Markdown Footnote** with the caret anywhere inside `[^n]` (including `[^|n]` and `[^n|]`), inside the `[^n]:` anchor, or in its body. A selection contained in one reference or definition works too. The command cuts the whole definition and every matching reference, renumbers the remaining notes, and puts the body on the clipboard. The final clipboard item has only ordinary text, so Tinycast and ClipEdge can capture it. No shortcut is assigned by default; use **Settings → Commands**.

**Body boundary:** as explicitly requested, an anchor owns every subsequent line through the next real footnote anchor or the end of the document. This includes unindented paragraphs and blank lines. Keep footnotes together at the end when using this convention; trailing prose after an anchor belongs to that note. This differs deliberately from Extract's standard indented-continuation parsing of existing definitions.

The clipboard omits the anchor and its colon, strips one structural tab/four-space continuation indent, and trims leading/trailing whitespace. Internal Markdown, parentheses, capitalization and paragraph breaks remain. References inside code or other masked syntax stay literal. Empty notes, ambiguous selections, missing/duplicate definitions and nested footnote references are refused. Repeated references to a lifted note all vanish. Removing the last note leaves no empty footnote block. Undo in the source restores the document; the lifted text remains on the clipboard.

## Editor support and delivery

These commands operate on plain-text Markdown. The generic accessibility path requires `AXValue`, a matching `AXNumberOfCharacters`, one valid `AXSelectedTextRange`, a writable selection range, and a writable value or selected-text attribute. A web selection marker alone does not disqualify a control that supplies those standard attributes. Secure fields, oversized buffers (over one million UTF-16 units), multiple selections and unsupported controls are refused. Tinycast's own editors are not supported yet. Whole-buffer plain-text replacement does not preserve rich-text formatting, embedded objects or editor metadata.

The generic path returns to the captured app, selects the complete buffer, waits up to half a second for its selection acknowledgment, rechecks focus/text/selection, and posts one Paste. Temporary clipboard items carry an internal marker; the original clipboard is restored only while the lease owns it. Lift instead commits its plain-text payload after exact edited-buffer readback. A failed clipboard commit restores the borrowed clipboard through the caller's deferred lease cleanup and reports uncertainty; use Undo before retrying. The source editor owns the undo transaction.

**Obsidian:** a dedicated adapter invokes the `obsidian-cli` bundled inside the running app. Obsidian's command-line interface must already be enabled. It captures the complete active Markdown editor, including text outside the viewport, and applies one `editor.transaction`. Before writing it rechecks vault, file, tab, editor focus, complete text and selection. Snapshot/payload files live briefly in a private temporary directory; document text is passed as JSON data, never interpolated into executable JavaScript. CLI calls have a five-second timeout. The adapter never enables the CLI or installs a plugin. API/CLI absence fails without falling back to a viewport-sized accessibility buffer. Other block/virtualized editors need their own complete-buffer integration.

Obsidian references: [Editor API](https://docs.obsidian.md/Plugins/Editor/Editor) and [CLI](https://obsidian.md/help/cli). Its DOM focus check uses the current CodeMirror content element and refuses capture if that interface is unavailable.

## Verification

`./Scripts/run-tests.sh footnote-transformer-test` compiles the shipped model files and checks selection boundaries, nested parentheses, Unicode, Markdown syntax, renumbering, repeated/named/orphan notes, multiline definitions, line endings and refusal paths. `footnote-lift-test` checks reference/anchor/body/EOF selection, all-reference removal, trimming, numbering and refusal paths. `obsidian-editor-script-test` executes the shipped JavaScript in JavaScriptCore and checks destination-change refusal. `snippets-test` covers the shared injection queue, final clipboard commit, intervening-copy protection and failed-copy restoration. Offscreen AppKit fixtures render the actual engine result in both appearances without opening a text app.

Live extraction, lift, renumbering and undo pass in TextEdit plain text, Chrome textarea and plain contenteditable controls, and a 20,400-character Obsidian Live Preview document. ClipEdge visibly captures the lifted plain text. Detailed evidence is recorded in the owning project. A matching accessibility count alone does not establish support for every virtualized editor; universal app support is not claimed.
