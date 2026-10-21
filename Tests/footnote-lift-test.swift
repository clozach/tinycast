import Foundation

@main @MainActor
struct FootnoteLiftTest {
    static var count = 0
    static var failed = 0

    static func main() {
        let input = "One[^old], again[^old]; two[^later].\n\n"
            + "[^old]:  first line  \n    second line\nthird line\n\n[^later]: Keep me."
        let expected = "One, again; two[^1].\n\n[^1]: Keep me."
        let clip = "first line  \nsecond line\nthird line"
        for position in 4...8 {
            check("reference caret \(position)", lift(input, at: position, equals: expected, clipboard: clip))
        }
        for position in (input as NSString).range(of: "[^old]:").location..<(input as NSString).range(of: "[^later]:").location {
            check("definition caret \(position)", lift(input, at: position, equals: expected, clipboard: clip))
        }
        check("selected reference", lift(input, range: NSRange(location: 3, length: 6), equals: expected, clipboard: clip))
        check("selected body text", lift(input, range: (input as NSString).range(of: "second line"),
            equals: expected, clipboard: clip))
        let only = "Text[^1].\n\n[^1]:   Note.   \n  "
        check("last definition and trimmed clipboard", lift(only, at: only.utf16.count, equals: "Text.", clipboard: "Note."))
        check("only orphan definition", lift("[^x]: Alone", at: 8, equals: "", clipboard: "Alone"))
        check("all references removed", lift("A[^X] B[^x]\n\n[^x]: C", at: 3, equals: "A B", clipboard: "C"))
        check("blank paragraphs and tab continuation", lift("A[^1]\n\n[^1]: First\n\n\tSecond\n\nThird", at: 3,
            equals: "A", clipboard: "First\n\nSecond\n\nThird"))
        for ending in ["\n", "\r\n", "\r"] {
            let text = "😀[^9] é[^8]\n\n[^9]: Keep\n\n[^8]: élève\n    NASA".replacingOccurrences(of: "\n", with: ending)
            check("unicode and \(ending.debugDescription)", lift(text, range: (text as NSString).range(of: "élève"),
                equals: "😀[^1] é\n\n[^1]: Keep".replacingOccurrences(of: "\n", with: ending),
                clipboard: "élève" + ending + "NASA"))
        }
        check("fake code reference retained", lift("`[^x]` yes[^x]\n\n[^x]: body", at: 12,
            equals: "`[^x]` yes", clipboard: "body"))
        check("fake fenced anchor does not truncate note", lift("A[^x]\n\n[^x]: First\n```\n[^fake]: Code\n```\nLast", at: 3,
            equals: "A", clipboard: "First\n```\n[^fake]: Code\n```\nLast"))
        check("renumber by document order", lift("B[^b] A[^a] X[^x]\n\n[^a]: A\n\n[^x]: X\n\n[^b]: B", at: 15,
            equals: "B[^1] A[^2] X\n\n[^1]: B\n\n[^2]: A", clipboard: "X"))
        for (name, text, range) in [
            ("outside reference", "A[^1]\n\n[^1]: Note", NSRange(location: 0, length: 0)),
            ("after closing bracket", "A[^1]\n\n[^1]: Note", NSRange(location: 5, length: 0)),
            ("across notes", input, NSRange(location: 5, length: 30)),
            ("missing definition", "A[^1]", NSRange(location: 3, length: 0)),
            ("duplicate definition", "A[^1]\n\n[^1]: One\n\n[^1]: Two", NSRange(location: 3, length: 0)),
            ("empty note", "A[^1]\n\n[^1]:  \n", NSRange(location: 3, length: 0)),
            ("nested reference", "A[^1]\n\n[^1]: note[^2]\n\n[^2]: nested", NSRange(location: 3, length: 0)),
            ("fake inline code reference", "`[^1]`\n\n[^1]: Note", NSRange(location: 3, length: 0)),
            ("mixed line endings", "A[^1]\r\n\n[^1]: Note", NSRange(location: 3, length: 0)),
            ("split surrogate", "😀[^1]\n\n[^1]: Note", NSRange(location: 1, length: 0)),
            ("negative range", input, NSRange(location: -1, length: 0)),
            ("out of range", input, NSRange(location: input.utf16.count + 1, length: 0))
        ] { check("refuses \(name)", refuses(text, range: range)) }
        print("\(count - failed)/\(count) footnote lift checks passed")
        if failed > 0 { exit(1) }
    }

    static func lift(_ text: String, at position: Int, equals expected: String, clipboard: String) -> Bool {
        lift(text, range: NSRange(location: position, length: 0), equals: expected, clipboard: clipboard)
    }

    static func lift(_ text: String, range: NSRange, equals expected: String, clipboard: String) -> Bool {
        guard let result = try? FootnoteLift.transform(text, selection: range) else { return false }
        return result.document == expected && result.clipboard == clipboard
    }

    static func refuses(_ text: String, range: NSRange) -> Bool {
        do { _ = try FootnoteLift.transform(text, selection: range); return false } catch { return true }
    }

    static func check(_ name: String, _ result: Bool) {
        count += 1
        if !result { failed += 1; print("FAIL \(name)") }
    }
}
