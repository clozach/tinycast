import SwiftUI

/// A press the caret can use is never swallowed by a grid that cannot move.
@main
@MainActor
struct PaletteHorizontalArrowTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ actual: Bool, _ expected: Bool, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    static func steps(_ modifiers: EventModifiers = [], from: Int, to: Int?) -> Bool {
        PaletteHorizontalArrow.stepsSelection(modifiers: modifiers, from: from, to: to)
    }

    static func main() {
        // A bare arrow, as an arrow key carries it, steps the grid.
        let arrow: EventModifiers = [.function, .numericPad]
        expect(steps(arrow, from: 3, to: 2), true, "← mid-grid steps left")
        expect(steps(arrow, from: 3, to: 4), true, "→ mid-grid steps right")
        expect(steps(from: 3, to: 2), true, "← with no flags at all steps left")

        // Al's report: the first tile, a query typed, ← did nothing.
        expect(steps(arrow, from: 0, to: 0), false, "← on the first tile goes to the caret")
        expect(steps(arrow, from: 9, to: 9), false, "→ on the last tile goes to the caret")

        // A list, or a screen without a grid, answers nil.
        expect(steps(arrow, from: 2, to: nil), false, "no grid: the caret keeps ←/→")

        // The caret's chords never step a grid, wherever the selection sits.
        let chords: [(EventModifiers, String)] = [
            ([.command], "⌘"), ([.option], "⌥"), ([.shift], "⇧"), ([.control], "⌃"),
            ([.command, .shift], "⌘⇧"), ([.option, .shift], "⌥⇧")
        ]
        for (chord, name) in chords {
            let flags = chord.union(arrow)
            expect(steps(flags, from: 3, to: 2), false, "\(name)← mid-grid goes to the caret")
            expect(steps(flags, from: 0, to: 0), false, "\(name)← on the first tile goes to the caret")
            expect(steps(flags, from: 3, to: 4), false, "\(name)→ mid-grid goes to the caret")
        }

        // Caps Lock is a state, not a chord.
        expect(steps(arrow.union(.capsLock), from: 3, to: 2), true, "Caps Lock leaves ← on the grid")

        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
