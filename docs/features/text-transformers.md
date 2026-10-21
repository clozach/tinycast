# Text transformers

## Invariants

- Transform a captured complete text buffer, including its UTF-16 selection. Never treat copied selection text as the document.
- Validate the source element, selection and original text after activation and again immediately before delivery. A changed source cancels delivery.
- Replace through one native paste on the existing serialized delivery queue. Never delete first or retry a failed whole-buffer paste with synthetic typing.
- Borrow the clipboard with the existing ownership-aware lease. Confirm success only when the target exposes the exact expected text.
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

## Editor support and delivery

This first trial is for plain-text Markdown. The focused external control must expose `AXValue`, a matching `AXNumberOfCharacters`, one valid `AXSelectedTextRange`, a writable selection range, and a writable value or selected-text attribute. Marker-based web selections are refused because their exposed text can lag. Secure fields, oversized buffers (over one million UTF-16 units), multiple selections and unsupported controls are refused. A browser page, block editor or virtualized editor that does not expose the complete buffer needs a dedicated adapter. Tinycast's own editors are not supported by this command yet. Do not use whole-buffer plain-text replacement to preserve rich-text formatting, embedded objects or editor metadata.

The command returns to the captured application, selects the complete captured buffer, checks it again, and posts one native Paste. Clipboard history is paused for the lease, and the original clipboard is restored only if the lease still owns it. The editor owns its undo transaction. On uncertain delivery, Tinycast reports that the result could not be confirmed; it does not retry or announce success. Check the editor before invoking again. A cancelled pre-paste selection is restored only while the original text and selection still match.

## Verification

`./Scripts/run-tests.sh footnote-transformer-test` compiles the shipped model files and checks selection boundaries, nested parentheses, Unicode, Markdown syntax, renumbering, repeated/named/orphan notes, multiline definitions, line endings and refusal paths. `snippets-test` covers the shared injection queue and clipboard-lease machinery. Offscreen AppKit fixtures render the actual engine result in both appearances without opening a text app.

Live command dispatch, paste, clipboard restoration and undo in each target editor still need a user-authorized check. A successful native accessibility snapshot is only evidence that the buffer can be read; it does not prove insertion or universal app support.
