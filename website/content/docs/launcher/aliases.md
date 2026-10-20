---
title: Aliases
description: Give any launcher entry a short name that comes first when you type it.
---

An alias is your own short name for a launcher entry. Type `ps` to get Photoshop, or `sh` to get the
shell script you run every morning.

Aliases work on **any** entry: apps, System Settings panes, commands, Quick Actions, quicklinks,
snippets, system actions, window commands and layouts, and extension commands.

## Setting one

Set aliases in **Settings**, in the alias field on the item's row. Every pane that lists launcher
items has this field, including Applications, System Settings, System Actions, Commands,
Quicklinks, Quick Actions and each feature's own command list. For extensions, the field is next to
each command's shortcut in **Settings → Extensions**.

Each entry can have one alias. The field has a button to clear it.

In this fork, **Teach This Item** in the <kbd>⌘</kbd><kbd>K</kbd> menu opens a focused Trigger field
for the selected launcher item. Type `DARK` for Toggle System Appearance, then press Return.
The item's action stays unchanged.

For a global route, assign **Teach Tinycast** a shortcut in **Settings → Commands**. Over an ordinary
launcher result, it teaches that item. Outside the launcher, it starts with clipboard text in Target:
type a trigger → choose Open or Paste → save. Open offers Default first, then compatible installed
apps. Running the Teach Tinycast command itself also starts a clipboard/manual target.

Web URLs fill the optional Title field from the page automatically. You can edit it without
changing the trigger. Results show the title, destination and trigger separately. Save never waits
for title lookup; an in-flight result may finish the unchanged saved item afterward. Your own title
edits, Undo or later target changes take precedence.

Return saves from Trigger; Command-Return saves from Target, where Return inserts a newline.
Escape or clicking outside cancels. Saved targets live in **Settings → Commands → Taught Targets**.
Save and Delete offer Undo; **Undo Last Teaching** in Commands keeps the latest change reversible
for the current app session. Teach rejects a duplicate trigger and shows which item already owns it.
The older Settings alias fields keep their existing behavior.

## How an alias ranks

- **Typing the whole alias exactly always puts that entry first**, no matter what you picked before
  or what else has that name.
- **Typing the start of an alias** ranks just above names that start the same way. Something you
  pick very often can still rank higher.
- A match in the **middle** of an alias ranks the same as the other names an app is known by.
- **Scattered letters never match an alias.** `ps` won't match an alias of `Pixelmator Studio` by
  skipping letters, because that would make short aliases useless.

The first rule matters most. A two-letter alias is only worth setting if it always comes first.

## In the list

An entry with an alias shows it as a small tag after its name, so you can see which entries you've
named.

## Backups and cleanup

Aliases are included in [backups](/docs/reference/backup).
Taught literal targets are included in Settings & Shortcuts too.

An alias is removed along with the thing it names. If you uninstall the app, delete the quicklink or
remove the extension, its alias is deleted too, so it can't linger and match nothing.

Raycast exports include an alias for each command. The
[importer](/docs/reference/import-from-raycast) brings over the aliases for apps.
