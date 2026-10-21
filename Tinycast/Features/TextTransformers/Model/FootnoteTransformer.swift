import Foundation

enum FootnoteTransformer {
    enum Failure: Error, Equatable {
        case invalidSelection, noEnclosingParentheses, emptyAside, mixedLineEndings
        case duplicateDefinition, missingDefinition, nestedFootnote, insideDefinition
    }

    static func transform(_ text: String, selection: NSRange) throws -> String {
        let document = try MarkdownSelection(text, selection: selection)
        let normalized = document.text
        let range = try enclosing(in: normalized, selection: document.range)
        let source = normalized as NSString
        var aside = source.substring(with: NSRange(location: range.location + 1, length: range.length - 2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !aside.isEmpty else { throw Failure.emptyAside }
        aside = sentenceCase(aside)
        guard MarkdownSyntaxMask.references(in: aside).isEmpty else { throw Failure.nestedFootnote }
        let existing = try MarkdownFootnotes.split(normalized)
        guard existing.body != "" else { throw Failure.insideDefinition }
        // Definitions are detached only after extraction so the original selection stays meaningful.
        let marker = freshLabel(in: normalized)
        var replacementRange = range
        var preceding = range.location
        while preceding > 0, [UInt16(32), 9].contains(source.character(at: preceding - 1)) { preceding -= 1 }
        if preceding > 0, source.character(at: preceding - 1) != 10 {
            replacementRange.location = preceding
            replacementRange.length = NSMaxRange(range) - preceding
        }
        var body = normalized
        guard let replacing = Range(replacementRange, in: body) else { throw Failure.invalidSelection }
        body.replaceSubrange(replacing, with: "[^\(marker)]")
        let split = try MarkdownFootnotes.split(body)
        guard MarkdownSyntaxMask.references(in: split.body).contains(where: { $0.label == marker }) else {
            throw Failure.insideDefinition
        }
        let result = try MarkdownFootnotes.render(
            body: split.body, definitions: split.definitions + [.init(label: marker, content: aside)])
        return document.restoringLineEndings(result)
    }

    private static func sentenceCase(_ text: String) -> String {
        let mask = MarkdownSyntaxMask.make(text)
        var offset = 0
        for index in text.indices {
            let character = text[index]
            // A code- or URL-led sentence keeps its first word verbatim; never rewrite code or names.
            if character.isLetter {
                guard !mask[offset] else { return text }
                var result = text
                result.replaceSubrange(index...index, with: String(character).uppercased())
                return result
            }
            offset += String(character).utf16.count
        }
        return text
    }

    private static func enclosing(in text: String, selection: NSRange) throws -> NSRange {
        let units = Array(text.utf16)
        let mask = MarkdownSyntaxMask.make(text)
        var opens: [Int] = []
        var found: NSRange?
        for index in units.indices where !mask[index] {
            if units[index] == 40 { opens.append(index) }
            if units[index] == 41, let start = opens.popLast() {
                let candidate = NSRange(location: start, length: index - start + 1)
                let encloses =
                    selection.length == 0
                    ? selection.location > start && selection.location <= index
                    : selection.location >= start && NSMaxRange(selection) <= index + 1
                if encloses, found == nil || candidate.length < found!.length { found = candidate }
            }
        }
        guard let found else { throw Failure.noEnclosingParentheses }
        return found
    }

    private static func freshLabel(in text: String) -> String {
        var label = "tinycast-aside"
        while text.localizedCaseInsensitiveContains("[^\(label)]") { label += "-new" }
        return label
    }
}
