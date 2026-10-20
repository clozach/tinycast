# Teach Tinycast

Teach gives an existing launcher item an intentional trigger, or saves a literal target to open or
paste. It is a fork feature. It does not expand text while typing in other apps.

## Invariants

- The shortcut names the selected ordinary launcher item, or creates a clipboard/manual target.
- Literal targets never pass through a template engine or a shell.
- Save is explicit; typing the trigger in another app does not expand it.
- A duplicate trigger is visible and blocked. Every Teach save/delete carries its inverse.
- The dialog focuses Trigger after AppKit makes its panel key, preserving native text editing.

## Use it

Assign a global shortcut to **Teach Tinycast** in **Settings → Commands**. No default binding is
installed or existing binding overwritten.

- **Name an existing action:** invoke Tinycast → find and select the item → press the Teach shortcut
  (or ⌘K → Teach This Item) → type a trigger such as `DARK` → Return. The visible Target is the
  existing item's name; its action cannot be changed in this form.
- **Save a URL or text:** copy it → press the Teach shortcut outside the launcher (or run the Teach
  Tinycast command) → type a trigger → choose Open or Paste → save. Target starts with clipboard
  text and can also be typed. Open defaults to the system handler; the picker lists compatible
  installed apps, including browsers for web URLs.
- **Name the result:** HTTP(S) targets suggest their page title automatically, such as **Service
  Gallery** for `http://t.local:5194`. The optional Title field is editable and separate from the
  trigger. Results show that title, the destination URL (or a short literal preview), and the trigger
  badge. Existing saved titles are preserved.
- **Use what you taught:** invoke Tinycast → type the trigger → Return. Exact aliases rank before
  titles and learned preferences, even when the target's name shares none of the trigger's letters.
- **Edit:** select the taught result → Teach shortcut or ⌘K → Teach This Item. Saved payloads also
  appear in **Settings → Commands → Taught Targets**.
- **Undo:** click Undo in the save/delete receipt. It fades after eight seconds. **Undo Last
  Teaching** in Commands remains available for this app session until the next Teach change or
  configuration restore. Existing item aliases can also be cleared in their Settings row.

Trigger starts focused. Return saves from Trigger; Return inserts a line break in Target.
Command-Return saves from either. Escape or clicking outside cancels without changing the parent
query or selection. Target scrolls so the whole payload is inspectable.

Title lookup never blocks Save. A lookup already in flight may finish that exact saved target's title
after the form closes; any later library write, Undo, deletion or edit prevents that late update.
Typing in Title takes ownership, including typing and then clearing it. A changed Target cancels the
old lookup. Cancellation stops it; failed lookup keeps the trigger as the result name and shows the
destination beneath it. No clipboard monitoring or background scan of the library is involved.

Triggers are trimmed and compared using the launcher's case/width/diacritic fold. Teach refuses a
trigger owned by another item and names that item. Changing an existing alias explicitly says what
will be replaced; Undo restores it. Legacy Settings alias fields and imported aliases retain their
existing duplicate semantics.

## Boundaries

`TeachSource` reports the actual selected ordinary launcher result. Calculator, emoji, fallback,
meeting and nested feature results do not become accidental targets. Running Teach Tinycast itself
always starts a clipboard/manual draft; it never teaches an alias for its own command.

`TaughtTarget` has a stable UUID and either `.paste` or `.open(application:)`. Text is stored verbatim,
including spaces, braces, Unicode and line breaks. Paste uses `TextInjector` and the captured
destination; it reports failure rather than trying a different app. Open uses `QuicklinkLauncher`
directly, without template expansion or shell interpretation. A URL/path is required for Open;
executable `javascript:`, `data:` and `vbscript:` schemes are rejected.

`TeachStore` owns `taught-targets.json` under this app's Application Support directory. Writes stage a
0600 file and atomically rename it; failed writes do not publish memory. A corrupt existing file is
reported and left untouched. Configuration backups include the library and the existing alias table.
Target validation/persistence precedes every other configuration mutation on restore.

`PageTitleFetcher` uses an ephemeral, cookie-less, credential-free session. It accepts HTTP(S) only,
checks status and HTML MIME type, permits at most five HTTP(S) redirects, and reads at most 256 KiB
with an eight-second resource timeout. Public HTTP remains subject to platform transport security.
`PageTitle` scans the bounded HTML prefix once, skipping comments, quoted attributes and inert
elements; it never renders HTML or executes JavaScript. `TeachTitleLoader` owns request generations
and manual title ownership, independently of the dialog coordinator.

`TeachChanges` pairs each save/delete with its inverse. Deletion removes alias, favorite, visibility
and ranking references; Undo restores those records for that entry without replacing unrelated
records. Undo refuses to reclaim an alias another item has taken since.

## Verification

`teach-test` exercises target classification, collision normalization, exact literal round-tripping,
stable IDs, browser persistence, private file mode, rejected imports, corrupt files and failed
commits. `dialog-panel-test` covers Target newlines, Trigger submit, Command-Return, IME composition
and editing Undo/Redo. `fuzz-test` checks `DARK` beats an exact-title rival despite the action's
unrelated name. All are registered in `Scripts/run-tests.sh`.
`page-title-test` covers malformed and inert HTML, entities, metadata limits, stale/edited/cancelled
drafts, immediate Save and Undo races, plus real local HTTP redirects, MIME and byte limits.

Native checks: confirm initial Trigger focus; teach a selected item and cancel back to its exact
query/selection; create a clipboard URL and choose Default/a named browser; paste literal multiline
text into a focused editor; verify duplicate feedback; save/delete/Undo; relaunch and reuse a saved
target. Verify the chosen global shortcut after checking system and app conflicts.
