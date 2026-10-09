# Application switching

Summon Tinycast with a chord, keep its modifiers down, and press the trigger key again.
The palette becomes a list of open applications with the previous application selected.

## Invariants

- Only a trigger that brings the hidden palette forward starts a gesture. Releasing any required
  modifier before the next press, or using another key, ends that gesture.
- The first subsequent press selects B. Given foreground history A, B, C, D, E, the list is
  B, A, C, D, E. The second subsequent press selects A, and further presses wrap forward.
  Adding Shift reverses later steps; the first subsequent press still selects B.
- Autorepeat and duplicate delivery of one press never advance the selection.
- While switching, activation waits for both the trigger key and all momentary modifiers to be up.
  Escape, including Command-Escape while Command remains held, dismisses to the original application.
- Typing, navigation keys, composition, clicking, scrolling, another shortcut or opening a menu or
  dialog cancels release activation. The application list remains searchable; Return activates
  its selection using the ordinary palette controls.
- The list is a temporary palette frame. Dismissal or activation restores the previous screen,
  query, selection and navigation stack before the normal Pop to Root Search timer starts.
- Tinycast and background-only agents are excluded. Hidden and minimized regular applications
  remain eligible. A target that has quit does not get relaunched.

## Windows of the selected app

Press Right while the app list is open to browse the selected app's windows. This also works
while the summon chord's Command modifier remains down. Drilling into windows cancels
release-to-switch, so releasing Command leaves the window list open.

The first list contains unminimized windows of that exact process. Hold Option to
include minimized windows and windows of a hidden app; release Option to narrow it again.
The current search is preserved during either change. Rows label **Minimized** and **Hidden**.
Simply type to filter by window title or app name. While Option is held, letter keys still
type ordinary filter letters, including Option dead keys. Modified navigation and Command
shortcuts retain their normal behavior.

Return opens the selected window. Option-Return works while hidden windows are included;
Tinycast unhides the app, unminimizes the window if needed, and raises that window.
Left with an empty filter returns to the app list, preserving its search and selection.
With a nonempty filter, Left edits the search. Escape or activation unwinds the temporary
app/window screens and restores the original palette state.

The app row shows **Windows →** and its Actions menu has **Show Windows**. This drill-down
is available independently of Settings → Navigation, which gates the standalone all-app
**Switch Windows** command. Windows on other Spaces remain eligible.

## Selection visibility

Keyboard selection changes request the palette's shared scroll-to-visible behavior through
`PaletteState.followToken`. `RootPaletteView` consumes that token, so held-trigger repeats,
Shift reversal and wraparound keep the highlighted app inside the space between the floating bars.
Arrow keys use the same scroll behavior. A row already visible stays in place; manual scrolling
remains free until the next keyboard selection step. The same token also serves window switching
and restored palette selections.

## Recall duration

The initial summon uses the existing **Settings → General → Pop to Root Search** delay.
Reopening before that delay preserves the previous palette state; reopening after it starts fresh.
This implementation does not change the preference or add a second recall timer.

## Ownership and event delivery

`AppCore` owns `AppRecencyMonitor` and `AppSwitchCoordinator`; the palette environment injects
the coordinator into its views. The monitor observes workspace
activation notifications, excluding Tinycast; it seeds its history from window stacking order
at launch. Full activation history becomes accurate as applications are used during the process's
lifetime. Regular applications with no known recency are appended alphabetically.

`AppSwitchGesture` owns the pure key-sequence decisions. `AppSwitchOrder` owns the head flip,
filtering and wrapped selection. `AppSwitchScreen` and `AppSwitchList` render that ordered snapshot
through the ordinary `PaletteScreen` interface.

`HotKeyManager` calls the coordinator before dispatching a registered chord and after it opens
the hidden palette. `HotKeyCenter` forwards Carbon press and release events. The palette's local
monitor handles Shift variants and ordinary activity. A cancellable task samples physical key and
modifier state every 16 milliseconds while the gesture is armed, because Carbon's chord-release
event can mean that one modifier was released while the trigger key is still down. No additional
event tap or permission is requested.

Modifier-only, double-tap and modifier-free bindings retain their existing behavior: they provide
no continuously held chord to repeat. A fresh chord while Tinycast is already visible likewise
keeps its normal command behavior.

## Verification

### System shortcut conflicts

If Shift-Space during a Command-held gesture opens Siri's image search, macOS has
claimed Shift-Command-Space for **Ask Siri about active window**. Open **System Settings →
Keyboard → Keyboard Shortcuts → Screenshots** and disable that shortcut, or double-click
its key combination and assign another one. **Ask Siri about selected area** remains
available on Shift-Command-6. Re-enabling the checkbox restores the system binding.

Tinycast's local event monitor cannot consume a key that the system captures first.
Changing the conflicting system assignment allows the same held gesture to reach Tinycast.

See Apple's [conflicting-shortcut instructions](https://support.apple.com/guide/mac-help/mchlp2864/mac)
and [keyboard shortcut reference](https://support.apple.com/en-us/102650).

### Checks

`app-switch-test` compiles the shipped pure models. It covers the B/A head flip, filtering,
both complete wrap cycles, duplicate and autorepeat delivery, Shift reversal, modifier continuity,
partial release, final-key release, cancellation and empty or single-app lists.

For a physical-key check, use two applications in succession (B then A). With Tinycast hidden,
hold Command and tap Space: the old palette returns. Tap Space again: B is highlighted above A.
Another tap selects A; Shift-Space goes back to B. With enough open apps to overflow, keep
stepping past the bottom: the highlight stays visible. Reverse and wrap in both directions to
check the top edge too. Release all keys to switch, then repeat with
Escape to return to A. In another gesture, press an arrow or type before releasing: the list stays
open, and Return performs the switch. Reopen within the configured delay to check the original
palette state survived.
