import Foundation

enum MarkdownFootnotes {
    struct Definition {
        let label: String
        let content: String
    }

    static func split(_ text: String) throws -> (body: String, definitions: [Definition]) {
        let source = text as NSString
        let mask = MarkdownSyntaxMask.make(text)
        let expression = try NSRegularExpression(pattern: #"(?m)^ {0,3}\[\^([^\]\s]+)\]:[ \t]*(.*)$"#)
        let headers = expression.matches(in: text, range: NSRange(location: 0, length: source.length))
            .filter { !mask[$0.range.location] }
        var definitions: [Definition] = []
        var removed: [NSRange] = []
        var labels = Set<String>()
        for header in headers {
            let label = source.substring(with: header.range(at: 1))
            guard labels.insert(label.lowercased()).inserted else { throw FootnoteTransformer.Failure.duplicateDefinition }
            var content = source.substring(with: header.range(at: 2))
            var end = NSMaxRange(header.range)
            while end < source.length {
                let next = end + 1
                guard next < source.length else { break }
                let lineEnd = source.range(of: "\n", range: NSRange(location: next, length: source.length - next))
                let last = lineEnd.location == NSNotFound ? source.length : lineEnd.location
                let line = source.substring(with: NSRange(location: next, length: last - next))
                if line.hasPrefix("    ") || line.hasPrefix("\t") {
                    content += "\n" + (line.hasPrefix("\t") ? String(line.dropFirst()) : String(line.dropFirst(4)))
                    end = last
                } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    guard hasContinuation(after: last, in: source) else { break }
                    content += "\n"
                    end = last
                } else {
                    break
                }
            }
            guard MarkdownSyntaxMask.references(in: content).isEmpty else {
                throw FootnoteTransformer.Failure.nestedFootnote
            }
            definitions.append(Definition(label: label, content: content))
            removed.append(NSRange(location: header.range.location, length: end - header.range.location))
        }
        var body = text
        for range in removed.reversed() {
            guard let swiftRange = Range(range, in: body) else { throw FootnoteTransformer.Failure.invalidSelection }
            body.removeSubrange(swiftRange)
        }
        return (body, definitions)
    }

    private static func hasContinuation(after offset: Int, in source: NSString) -> Bool {
        var start = offset + 1
        while start < source.length {
            let newline = source.range(of: "\n", range: NSRange(location: start, length: source.length - start))
            let end = newline.location == NSNotFound ? source.length : newline.location
            let line = source.substring(with: NSRange(location: start, length: end - start))
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                return line.hasPrefix("    ") || line.hasPrefix("\t")
            }
            start = end + 1
        }
        return false
    }

    static func render(body: String, definitions: [Definition]) throws -> String {
        let byLabel = Dictionary(uniqueKeysWithValues: definitions.map { ($0.label.lowercased(), $0) })
        let references = MarkdownSyntaxMask.references(in: body)
        var order: [String] = []
        var numbers: [String: Int] = [:]
        for reference in references {
            let label = reference.label.lowercased()
            guard byLabel[label] != nil else { throw FootnoteTransformer.Failure.missingDefinition }
            if numbers[label] == nil {
                order.append(label)
                numbers[label] = order.count
            }
        }
        for definition in definitions where numbers[definition.label.lowercased()] == nil {
            let label = definition.label.lowercased()
            order.append(label)
            numbers[label] = order.count
        }
        var result = body
        for reference in references.reversed() {
            guard let range = Range(reference.range, in: result) else { throw FootnoteTransformer.Failure.invalidSelection }
            result.replaceSubrange(range, with: "[^\(numbers[reference.label.lowercased()]!)]")
        }
        while result.hasSuffix("\n") { result.removeLast() }
        let notes = order.map { label -> String in
            let lines = byLabel[label]!.content.components(separatedBy: "\n")
            let continuation = lines.dropFirst().map { $0.isEmpty ? "" : "    " + $0 }.joined(separator: "\n")
            return "[^\(numbers[label]!)]: " + lines[0] + (lines.count > 1 ? "\n" + continuation : "")
        }
        return result + "\n\n" + notes.joined(separator: "\n\n")
    }
}
