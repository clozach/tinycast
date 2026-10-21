import Foundation

enum FootnoteLift {
    enum Failure: Error { case noFootnote, emptyFootnote }

    struct Result {
        let document: String
        let clipboard: String
    }

    static func transform(_ text: String, selection: NSRange) throws -> Result {
        let document = try MarkdownSelection(text, selection: selection)
        let source = document.text as NSString
        let headers = try MarkdownFootnotes.definitionHeaders(in: document.text)
        var definitions: [MarkdownFootnotes.Definition] = []
        var labels = Set<String>()
        var selectedLabel: String?
        for (index, header) in headers.enumerated() {
            let label = source.substring(with: header.range(at: 1)).lowercased()
            guard labels.insert(label).inserted else { throw FootnoteTransformer.Failure.duplicateDefinition }
            let end = index + 1 < headers.count ? headers[index + 1].range.location : source.length
            let start = header.range(at: 2).location
            let content = body(source.substring(with: NSRange(location: start, length: end - start)))
            guard MarkdownSyntaxMask.references(in: content).isEmpty else {
                throw FootnoteTransformer.Failure.nestedFootnote
            }
            definitions.append(.init(label: label, content: content))
            if contains(document.range, start: header.range.location, end: end, includesEnd: end == source.length) {
                selectedLabel = label
            }
        }
        let bodyEnd = headers.first?.range.location ?? source.length
        var remaining = source.substring(to: bodyEnd)
        let references = MarkdownSyntaxMask.references(in: remaining)
        for reference in references {
            guard labels.contains(reference.label.lowercased()) else { throw FootnoteTransformer.Failure.missingDefinition }
            if contains(document.range, start: reference.range.location, end: NSMaxRange(reference.range)) {
                selectedLabel = reference.label.lowercased()
            }
        }
        guard let selectedLabel, let lifted = definitions.first(where: { $0.label == selectedLabel }) else {
            throw Failure.noFootnote
        }
        guard !lifted.content.isEmpty else { throw Failure.emptyFootnote }
        for reference in references.reversed() where reference.label.lowercased() == selectedLabel {
            guard let range = Range(reference.range, in: remaining) else {
                throw FootnoteTransformer.Failure.invalidSelection
            }
            remaining.removeSubrange(range)
        }
        let result = try MarkdownFootnotes.render(
            body: remaining, definitions: definitions.filter { $0.label != selectedLabel })
        return Result(
            document: document.restoringLineEndings(result),
            clipboard: document.restoringLineEndings(lifted.content))
    }

    private static func contains(_ range: NSRange, start: Int, end: Int, includesEnd: Bool = false) -> Bool {
        range.location >= start && NSMaxRange(range) <= end
            && (range.length > 0 || range.location < end || includesEnd)
    }

    private static func body(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let continuation = lines.dropFirst().map { line in
            if line.hasPrefix("    ") { return String(line.dropFirst(4)) }
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            return line
        }
        return ([lines[0]] + continuation).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
