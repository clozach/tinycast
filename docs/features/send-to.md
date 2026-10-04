# Send to

Press **⇧⌘S** anywhere in Tinycast to send the current content to another app. The palette also has a
**Send to…** button in its footer; titled windows have **Edit → Send to…**. This is an app-local
shortcut, so it does not take the same chord from other apps. Tab keeps its existing navigation role.
Shortcut recording and an open Tinycast confirmation dialog retain ownership of input until closed.

The chooser shows the source and a short preview. Type an app name to filter, use ↑/↓ to select it,
and press Return or click the row. Escape, Back, or Left with an empty search returns to the original
screen with its query and highlighted result intact. Clicking another app dismisses both the chooser
and its source palette. Opening or cancelling the chooser leaves the clipboard unchanged.

- **Open in** lists apps macOS says can open every selected file or the link, with the default first.
  Multiple installations of the same app share one row; the preferred compatible installation wins.
- **Paste into** lists running regular apps, most recently frontmost first. Tinycast copies the content,
  activates the chosen app, waits for it to take focus, and sends Paste to that process. The destination
  needs a suitable input area; this action never presses Return or sends a message there.

Paste needs Tinycast's existing Accessibility permission. A closed or unavailable destination reports
an error; a focus timeout does not redirect the paste to another app. A failed paste leaves the copied
content on the clipboard for manual use.

## Which content is sent

A selected passage in a content editor or preview wins. Palette search text is a query, so its highlight
does not replace the selected result. Without a passage, each screen supplies its current item:

| Surface | Content |
| --- | --- |
| Launcher | Calculation answer, formatted color, emoji, file/app bundle, meeting link, or concrete link/snippet |
| Clipboard | The selected text, image, or file |
| Files | The selected file or folder |
| Emoji | The selected glyph with the chosen skin tone |
| Snippets / Quicklinks | The concrete text, URL, or file; unresolved templates are not executed |
| Contacts | The selected card's name, or the selected field's value |
| Calendar | The selected meeting link |
| Dictionary / Calculator History | The definition or formatted answer |
| Quick AI / AI Chat | The latest assistant response |
| Chat History | The selected conversation as Markdown |
| Notes | The current note's unsaved Markdown |
| Extensions | Content declared by standard Copy, Paste, Open, Open With, or Show in Finder actions; otherwise Detail Markdown |

Screens without sendable content use a frozen copy of the **clipboard**, explicitly labelled
“Clipboard.” This includes commands, empty results, Settings with no selected text, and opaque custom
extension actions. Tinycast does not invoke a command or extension callback to guess its output.
Concealed extension Copy actions do not expose their content to this feature. Clipboard fallback
preserves rich representations and multiple files, even if another app changes the clipboard while
the chooser is open.

For example, Unimagic's custom learning-and-paste callbacks are opaque, so its grid uses Clipboard;
Tinycast's built-in emoji results supply their selected glyph directly.

## Ownership

`AppCore` owns `SendToCoordinator`. `SendToSource` registers a weak per-window source whose callback is
refreshed with the view. `PaletteScreen.sendToPayload(at:)` reads the same rows the user sees; Notes and
AI Chat register their own content. A local key monitor makes the command available even in
non-activating panels and text editors, while shortcut recording keeps ownership of recorded keys.

`SendToService` resolves targets and delivers content. Its injected sources and effects let the
standalone harness test focus changes, cancellation and clipboard snapshots without activating apps or
writing the user's clipboard. Clipboard image exports use a dedicated temporary staging directory;
old exports expire on a later image use, allowing receiving apps time to read them.

Extension metadata is added by the convenience-action adapters in
`Scripts/raycast-runtime/src/api/components.js`. `ExtensionSendTo` reads that inert data inside the
Extensions feature; extension presentation remains isolated from shared native UI.

## Verification

- With `2+2` in the launcher, press ⇧⌘S: the preview says `4`. Filter for a text editor and paste there.
- Reopen `2+2`, click Send to, then Escape: the original query and result remain.
- From File Search or a URL result, check Open in and Paste into. Opening a file uses the chosen app.
- From Emoji and an extension with a standard Copy action, verify the preview is the selected content.
- Select a passage in Notes, press ⇧⌘S, and check that only the passage is offered. With no selection,
  check that the current note is offered. Repeat in the AI Chat window with a selected passage.
- From a screen with no sendable item, verify “Clipboard” appears and the preview matches the clipboard.
- In Search apps, ⌘A selects the whole query. Escape and Back return without changing the clipboard.
- While composing text with an IME, Return commits composition before it can send anything.
- Click another app while the chooser is open: the chooser and source palette both disappear.
- Run `Scripts/run-tests.sh`, `Scripts/lint.sh`, the Model import check, and a Debug build.
