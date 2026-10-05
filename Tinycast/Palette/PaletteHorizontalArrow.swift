import SwiftUI

/// ←/→ on a screen with both a search caret and a grid: one rule, so neither can starve the other.
enum PaletteHorizontalArrow {
    /// The caret's own chords (⌘← to the start, ⌥← by word, ⇧← to select) always edit the query.
    /// A plain arrow steps the grid, and goes to the caret when the step cannot leave its cell, so a
    /// press at the grid's edge is never swallowed while the caret blinks beside it.
    static func stepsSelection(modifiers: EventModifiers, from selection: Int, to target: Int?) -> Bool {
        guard modifiers.isDisjoint(with: [.command, .option, .shift, .control]) else { return false }
        guard let target else { return false }
        return target != selection
    }
}
