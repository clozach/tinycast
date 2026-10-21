import Foundation

struct MarkdownSelection {
    let text: String
    let range: NSRange
    let newline: String

    init(_ source: String, selection: NSRange) throws {
        guard selection.location >= 0, selection.length >= 0,
            selection.location <= source.utf16.count,
            selection.length <= source.utf16.count - selection.location,
            Self.isScalarBoundary(selection.location, in: source),
            Self.isScalarBoundary(NSMaxRange(selection), in: source),
            let selected = Range(selection, in: source)
        else { throw FootnoteTransformer.Failure.invalidSelection }
        newline = try Self.lineEnding(in: source)
        text = source.replacingOccurrences(of: newline, with: "\n")
        let start = source[..<selected.lowerBound].replacingOccurrences(of: newline, with: "\n").utf16.count
        let length = source[selected].replacingOccurrences(of: newline, with: "\n").utf16.count
        range = NSRange(location: start, length: length)
    }

    func restoringLineEndings(_ result: String) -> String {
        result.replacingOccurrences(of: "\n", with: newline)
    }

    private static func isScalarBoundary(_ offset: Int, in text: String) -> Bool {
        guard offset < text.utf16.count else { return true }
        let unit = text.utf16[text.utf16.index(text.utf16.startIndex, offsetBy: offset)]
        return !(0xDC00...0xDFFF).contains(unit)
    }

    private static func lineEnding(in text: String) throws -> String {
        let withoutPairs = text.replacingOccurrences(of: "\r\n", with: "")
        if text.contains("\r\n") {
            guard !withoutPairs.contains("\n"), !withoutPairs.contains("\r") else {
                throw FootnoteTransformer.Failure.mixedLineEndings
            }
            return "\r\n"
        }
        if text.contains("\r") {
            guard !text.contains("\n") else { throw FootnoteTransformer.Failure.mixedLineEndings }
            return "\r"
        }
        return "\n"
    }
}
