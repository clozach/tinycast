# Contacts

`Search Contacts` lists every card in Contacts and ranks it by the query (`.contacts`). Its own
shortcut, pressed again on a card, replaces the list with that card's fields (`.contactFields`): one
key digs one level deeper, the way LaunchBar's contact search does, and the way Unimagic's second
⌥⌘G opens its skin tones. Escape walks back to the list with its search intact. Everything is read
locally through the Contacts framework — no network, no copy on disk.

## Invariants

- **Access is asked on first use, never at launch.** `ContactsStore.prepare()` runs each time the
  screen opens: TCC sends nothing when a grant changes, so access is read again every time. A first
  open asks; a denial empties the list and the empty state says why rather than "No matching contacts".
  The hardened runtime needs `com.apple.security.personal-information.addressbook`, and
  `NSContactsUsageDescription` is the sentence macOS shows in the prompt.
- **The address book is read off the main actor and held in memory.** `fetchAll()` runs detached and
  flattens each `CNContact` into a `ContactCard`; `.CNContactStoreDidChange` re-reads it, so an edit in
  Contacts shows on the next keystroke. Nothing is persisted.
- **`ContactSearch` is the only ranking.** A name hit beats a company hit beats an email or a number,
  and a subsequence match counts as no match: in an address book, `lvlc` finding Lovelace is noise.
  Names and companies also match without their apostrophes, so `lozach` finds Lozac'h as a word
  start rather than ranking below a mid-word hit. A query that reads as a number (digits, spaces,
  `+ - ( ) .`) with three or more digits also matches a number stripped to its digits, so `5551234`
  finds `(415) 555-1234`; `955 dre` is a name and dials nothing. `contacts-test` pins the order.
- **The shortcut is the sub-search key.** `ContactsCoordinator.runShortcut()`: from anywhere it opens
  the list (carrying a typed root search, see [hotkeys.md](hotkeys.md)); on the list with a card
  selected it pushes that card's fields; on the fields it closes the palette. ⌘I does the same push for
  a launch from the list, where there is no shortcut to press.
- **A reopen within the Remember window starts on the last card.** Acting on a card (opening it,
  showing its fields, calling, writing, mapping, messaging or copying) records it as a
  `ContactRecall`, with the search that found it. Search Contacts opened within Settings › General ›
  *Remember last contact* (Off, or 1–30 minutes; 5 by default; `general.contactsRecallMinutes` in
  settings.json) reopens on that search, selected, with the card selected: the next match is one
  arrow away, typing replaces the search, and ⌥⌘A digs straight back in. A card picked without a
  search reopens on its name. Root text a hotkey carries in wins over the name; the recall is held in memory
  only, so a relaunch forgets it. `contacts-test` pins the window's edges.
- **A field's ↵ is what the field is for.** Call (`tel:`), Write Email (`mailto:`), Show in Maps
  (`maps://?q=`), Open Link; a birthday copies. ⌘↵ always copies the value.

## Actions

| Screen | Key | Does |
| --- | --- | --- |
| list | ↵ | Open in Contacts — `addressbook://<identifier>` |
| list | ⌘I, or the command's shortcut | Show Fields — the card's phones, emails, addresses, links and birthday |
| list | ⌘↵ | Copy Name |
| fields | ↵ | the field's own action (above) |
| fields | ⌘↵ | Copy the value |
| fields | ⌘K | also Send Message (`sms:`) for a number or address, and Open in Contacts |

Typing on the fields screen filters them by value or label (`mobile`, `home`).
