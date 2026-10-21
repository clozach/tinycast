import Foundation

@main @MainActor struct FootnoteTransformerTests {
    static var count = 0
    static var failed = 0
    static func main() {
        expect("basic", "Hello (a NASA pilot) world.", "NASA", "Hello[^1] world.\n\n[^1]: A NASA pilot")
        expect("nested smallest", "Hello (outer (inner aside) end).", "inner", "Hello (outer[^1] end).\n\n[^1]: Inner aside")
        expect(
            "full aside keeps inner", "Hello (outer (inner) end).", "(outer (inner) end)",
            "Hello[^1].\n\n[^1]: Outer (inner) end")
        expect(
            "document order", "First (new aside). Later[^9] again[^9].\n\n[^9]: Existing.", "new",
            "First[^1]. Later[^2] again[^2].\n\n[^1]: New aside\n\n[^2]: Existing.")
        expect(
            "named labels", "First[^z]. Then (a new aside).\n\n[^z]: Existing.", "new",
            "First[^1]. Then[^2].\n\n[^1]: Existing.\n\n[^2]: A new aside")
        expect("unicode", "🪷 café (élan and NASA) end", "NASA", "🪷 café[^1] end\n\n[^1]: Élan and NASA")
        expect(
            "multiline aside", "Start (line one\nline two\n\nparagraph two) end.", "line one",
            "Start[^1] end.\n\n[^1]: Line one\n    line two\n\n    paragraph two")
        expect(
            "multiline existing", "Start (new). Later[^x].\n\n[^x]: First\n    second\n\n    third\n\nAfter.", "new",
            "Start[^1]. Later[^2].\n\n\n\nAfter.\n\n[^1]: New\n\n[^2]: First\n    second\n\n    third")
        expect(
            "orphan preserved", "Text (new).\n\n[^unused]: Preserve me.", "new",
            "Text[^1].\n\n[^1]: New\n\n[^2]: Preserve me.")
        expect("CRLF", "Text (new).\r\n\r\nOther.", "new", "Text[^1].\r\n\r\nOther.\r\n\r\n[^1]: New")
        expect("CR", "Text (new).\rOther.", "new", "Text[^1].\rOther.\r\r[^1]: New")
        expect(
            "code references untouched", "Text (new) `[^fake]`.\n\n```md\n[^alsofake]\n```", "new",
            "Text[^1] `[^fake]`.\n\n```md\n[^alsofake]\n```\n\n[^1]: New")
        expect("escaped reference untouched", "Text (new) \\[^fake].", "new", "Text[^1] \\[^fake].\n\n[^1]: New")
        expect("code parens inside aside", "Text (the `f(x)` call) end.", "call", "Text[^1] end.\n\n[^1]: The `f(x)` call")
        expect(
            "link destination inside aside", "Text (see [link](https://example.org/a(b))) end.", "see",
            "Text[^1] end.\n\n[^1]: See [link](https://example.org/a(b))")
        expect("emoji before aside", "🪷 (aside)", "aside", "🪷[^1]\n\n[^1]: Aside")
        expect("horizontal spaces", "Text   (aside)", "aside", "Text[^1]\n\n[^1]: Aside")
        expect("leading indentation", "  (aside)", "aside", "  [^1]\n\n[^1]: Aside")
        expect("leading blank lines", "\n\nText (aside)", "aside", "\n\nText[^1]\n\n[^1]: Aside")
        expect("leading code unchanged", "Text (`foo()` does it)", "does", "Text[^1]\n\n[^1]: `foo()` does it")
        expect("marked sentence", "Text (**a** NASA pilot)", "NASA", "Text[^1]\n\n[^1]: **A** NASA pilot")
        expect(
            "link definition unchanged", "Text (aside).\n\n[url]: https://example.org/a(b)", "aside",
            "Text[^1].\n\n[url]: https://example.org/a(b)\n\n[^1]: Aside")
        reject("link definition", "[url]: https://example.org/a(b)", "(b)", .noEnclosingParentheses)
        reject("autolink", "<https://example.org/a(b)>", "(b)", .noEnclosingParentheses)
        reject("HTML attribute", "<span title=\"(aside)\">word</span>", "aside", .noEnclosingParentheses)
        reject("inside definition", "Text[^a].\n\n[^a]: An (aside).", "aside", .nestedFootnote)
        reject("wiki target", "See [[Book (edition)]].", "edition", .noEnclosingParentheses)
        reject("inline math", "Use $f(x)$ here.", "(x)", .noEnclosingParentheses)
        reject("frontmatter", "---\ntitle: A (draft)\n---\nText.", "draft", .noEnclosingParentheses)
        reject("quoted fence", "> ~~~\n> (code)\n> ~~~", "code", .noEnclosingParentheses)
        reject("listed fence", "- ~~~\n  (code)\n  ~~~", "code", .noEnclosingParentheses)
        expect(
            "spaces on blank continuation", "Text (new)[^a].\n\n[^a]: First\n\n  \n    Second", "new",
            "Text[^1][^2].\n\n[^1]: New\n\n[^2]: First\n\n\n    Second")
        reject("no enclosing", "No aside here", "aside", .noEnclosingParentheses)
        reject("inline code", "Text `(code)` end", "code", .noEnclosingParentheses)
        reject("fenced code", "```\n(inside code)\n```", "inside", .noEnclosingParentheses)
        reject("indented code", "    (inside code)", "inside", .noEnclosingParentheses)
        reject("link destination", "[a](https://example.org)", "example", .noEnclosingParentheses)
        reject("comment", "<!-- (aside) -->", "aside", .noEnclosingParentheses)
        reject("escaped parens", "Text \\(not aside\\)", "not", .noEnclosingParentheses)
        reject("duplicate definitions", "Text (new)[^a].\n\n[^a]: One\n\n[^a]: Two", "new", .duplicateDefinition)
        reject("missing definition", "Text (new)[^a].", "new", .missingDefinition)
        reject("nested reference", "Text (new)[^a].\n\n[^a]: Nested[^b]\n\n[^b]: Other", "new", .nestedFootnote)
        reject("mixed newlines", "Text (new).\r\nOther\n", "new", .mixedLineEndings)
        reject("empty aside", "Text () end", "()", .emptyAside)
        reject("selection crosses siblings", "(one) and (two)", "one) and (two", .noEnclosingParentheses)
        check(
            "caret inside",
            (try? FootnoteTransformer.transform("Text (aside)", selection: NSRange(location: 8, length: 0)))
                == "Text[^1]\n\n[^1]: Aside")
        check("caret after", fails("(aside)", NSRange(location: 7, length: 0), .noEnclosingParentheses))
        check("invalid range", fails("(aside)", NSRange(location: 100, length: 2), .invalidSelection))
        check("split surrogate", fails("🪷 (aside)", NSRange(location: 1, length: 1), .invalidSelection))
        check("negative range", fails("(aside)", NSRange(location: -1, length: 1), .invalidSelection))
        print("\(count - failed)/\(count) passed")
        exit(failed == 0 ? 0 : 1)
    }
    static func expect(_ name: String, _ input: String, _ selection: String, _ output: String) {
        do {
            let actual = try FootnoteTransformer.transform(input, selection: (input as NSString).range(of: selection))
            check(name, actual == output)
            if actual != output { print("actual: \(actual.debugDescription)\nexpected: \(output.debugDescription)") }
        } catch { check(name + " threw \(error)", false) }
    }
    static func reject(_ name: String, _ input: String, _ selection: String, _ error: FootnoteTransformer.Failure) {
        check(name, fails(input, (input as NSString).range(of: selection), error))
    }
    static func fails(_ text: String, _ range: NSRange, _ expected: FootnoteTransformer.Failure) -> Bool {
        do {
            _ = try FootnoteTransformer.transform(text, selection: range)
            return false
        } catch { return error as? FootnoteTransformer.Failure == expected }
    }
    static func check(_ name: String, _ result: Bool) {
        count += 1
        if !result {
            failed += 1
            print("FAIL \(name)")
        }
    }
}
