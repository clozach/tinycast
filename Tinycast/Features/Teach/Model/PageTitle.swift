import Foundation

/// Metadata is plain text. Parsing never renders HTML or evaluates page code.
enum PageTitle {
    static let maximumBytes = 256 * 1024

    static func url(_ target: String) -> URL? {
        guard case .web(let url) = TeachPolicy.openDestination(target),
            ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            url.user == nil, url.password == nil
        else { return nil }
        return url
    }

    static func parse(_ html: String) -> String? {
        guard let raw = titleContent(html) else { return nil }
        let decoded = entities(raw)
        let safe = String(decoded.unicodeScalars.filter {
            (!CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0))
                && !(0x202A...0x202E).contains($0.value) && !(0x2066...0x2069).contains($0.value)
        })
        let title = safe.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return title.isEmpty ? nil : String(title.prefix(240))
    }

    /// Advance over each region once. Regex backtracking over malformed HTML can be quadratic.
    private static func titleContent(_ html: String) -> String? {
        var cursor = html.startIndex
        var templateDepth = 0
        let rawElements = ["script", "style", "textarea", "xmp", "iframe", "noembed", "noframes"]
        while let start = html[cursor...].firstIndex(of: "<") {
            if html[start...].hasPrefix("<!--") {
                guard let end = html.range(of: "-->", range: start..<html.endIndex) else { return nil }
                cursor = end.upperBound
                continue
            }
            guard let tag = tag(in: html, from: start) else { return nil }
            cursor = tag.end
            if tag.name == "template" {
                templateDepth = max(0, templateDepth + (tag.closing ? -1 : 1))
            } else if !tag.closing, rawElements.contains(tag.name) {
                guard let close = closingTag(tag.name, in: html, from: cursor) else { return nil }
                cursor = close.upperBound
            } else if !tag.closing, tag.name == "plaintext" {
                return nil
            } else if !tag.closing, tag.name == "title", templateDepth == 0 {
                guard let close = closingTag("title", in: html, from: cursor) else { return nil }
                return String(html[cursor..<close.lowerBound])
            }
        }
        return nil
    }

    private static func tag(in html: String, from start: String.Index)
        -> (name: String, closing: Bool, end: String.Index)?
    {
        var cursor = html.index(after: start)
        let closing = cursor < html.endIndex && html[cursor] == "/"
        if closing { cursor = html.index(after: cursor) }
        let nameStart = cursor
        while cursor < html.endIndex, html[cursor].isLetter || html[cursor].isNumber || "-:".contains(html[cursor]) {
            cursor = html.index(after: cursor)
        }
        let name = html[nameStart..<cursor].lowercased()
        var quote: Character?
        while cursor < html.endIndex {
            let character = html[cursor]
            if let current = quote {
                if character == current { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return (name, closing, html.index(after: cursor))
            } else if character == "<" {
                return ("", false, cursor)
            }
            cursor = html.index(after: cursor)
        }
        return nil
    }

    private static func closingTag(_ name: String, in html: String, from start: String.Index) -> Range<String.Index>? {
        var cursor = start
        while let marker = html.range(of: "</" + name, options: .caseInsensitive, range: cursor..<html.endIndex) {
            var end = marker.upperBound
            while end < html.endIndex, html[end].isWhitespace { end = html.index(after: end) }
            if end < html.endIndex, html[end] == ">" { return marker.lowerBound..<html.index(after: end) }
            cursor = marker.upperBound
        }
        return nil
    }

    private static func entities(_ text: String) -> String {
        let named = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
            "ndash": "–", "mdash": "—", "hellip": "…", "copy": "©", "reg": "®",
            "laquo": "«", "raquo": "»", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”"
        ]
        guard let expression = try? NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);"#)
        else { return text }
        var result = text
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result),
                let valueRange = Range(match.range(at: 1), in: result) else { continue }
            let value = String(result[valueRange])
            let scalar = value.hasPrefix("#x") ? UInt32(value.dropFirst(2), radix: 16)
                : value.hasPrefix("#") ? UInt32(value.dropFirst()) : nil
            if let replacement = scalar.flatMap(UnicodeScalar.init).map(String.init) ?? named[value] {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }
}
