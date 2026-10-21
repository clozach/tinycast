import Foundation

// UTF-16 offsets keep Markdown syntax and macOS selections in the same coordinate space.
enum MarkdownSyntaxMask {
    static func make(_ text: String) -> [Bool] {
        let units = Array(text.utf16)
        var hidden = Array(repeating: false, count: units.count)
        var fence: (character: UInt16, count: Int)?
        var lineStart = 0
        while lineStart < units.count {
            let end = units[lineStart...].firstIndex(of: 10) ?? units.count
            var first = lineStart
            while first < end && units[first] == 32 { first += 1 }
            let indent = first - lineStart
            while first < end && units[first] == 62 {
                first += 1
                while first < end && units[first] == 32 { first += 1 }
            }
            if first + 1 < end, [UInt16(45), 43, 42].contains(units[first]), units[first + 1] == 32 {
                first += 2
            }
            if let open = fence {
                mark(lineStart..<min(end + 1, units.count), in: &hidden)
                let count = run(open.character, from: first, in: units)
                if indent <= 3, count >= open.count,
                    units[min(first + count, end)..<end].allSatisfy({ $0 == 32 || $0 == 9 })
                {
                    fence = nil
                }
            } else if indent <= 3, first < end, [UInt16(96), 126].contains(units[first]),
                run(units[first], from: first, in: units) >= 3
            {
                fence = (units[first], run(units[first], from: first, in: units))
                mark(lineStart..<min(end + 1, units.count), in: &hidden)
            } else if indent >= 4 || (first < end && units[first] == 9) {
                mark(lineStart..<end, in: &hidden)
            }
            lineStart = end + 1
        }
        let metadata = try? NSRegularExpression(pattern: #"\A---[ \t]*\n[\s\S]*?\n(?:---|\.\.\.)[ \t]*(?:\n|\z)"#)
        if let match = metadata?.firstMatch(in: text, range: NSRange(location: 0, length: units.count)) {
            mark(match.range.location..<NSMaxRange(match.range), in: &hidden)
        }
        var index = 0
        while index < units.count {
            if hidden[index] {
                index += 1
                continue
            }
            if units[index] == 92, index + 1 < units.count {
                hidden[index] = true
                hidden[index + 1] = true
                index += 2
                continue
            }
            if starts([60, 33, 45, 45], at: index, in: units) {
                var end = index + 4
                while end < units.count && !starts([45, 45, 62], at: end, in: units) { end += 1 }
                end = min(end + 3, units.count)
                mark(index..<end, in: &hidden)
                index = end
                continue
            }
            // HTML tags and Markdown autolinks are syntax, not parenthetical prose.
            if units[index] == 60, index + 1 < units.count,
                let end = units[(index + 1)...].firstIndex(of: 62),
                !units[index..<end].contains(10)
            {
                mark(index..<(end + 1), in: &hidden)
                index = end + 1
                continue
            }
            if starts([91, 91], at: index, in: units) {
                var end = index + 2
                while end < units.count && !starts([93, 93], at: end, in: units) { end += 1 }
                if end < units.count {
                    mark(index..<(end + 2), in: &hidden)
                    index = end + 2
                    continue
                }
            }
            if units[index] == 96 || units[index] == 36 {
                let delimiter = units[index]
                let count = run(delimiter, from: index, in: units)
                var end = index + count
                while end < units.count {
                    if delimiter == 36, units[end] == 92 {
                        end += 2
                        continue
                    }
                    let closing = run(delimiter, from: end, in: units)
                    if closing == count { break }
                    end += max(1, closing)
                }
                if end < units.count {
                    mark(index..<(end + count), in: &hidden)
                    index = end + count
                    continue
                }
                index += count
                continue
            }
            if units[index] == 93, index + 1 < units.count, units[index + 1] == 40 {
                var end = index + 2
                var depth = 1
                while end < units.count && depth > 0 {
                    if units[end] == 92 {
                        end += 2
                        continue
                    }
                    if units[end] == 40 { depth += 1 }
                    if units[end] == 41 { depth -= 1 }
                    end += 1
                }
                if depth == 0 {
                    mark((index + 1)..<end, in: &hidden)
                    index = end
                    continue
                }
            }
            index += 1
        }
        let links = try? NSRegularExpression(pattern: #"(?m)^ {0,3}\[(?!\^)[^\]\n]+\]:[^\n]*"#)
        for link in links?.matches(in: text, range: NSRange(location: 0, length: units.count)) ?? [] {
            mark(link.range.location..<NSMaxRange(link.range), in: &hidden)
        }
        return hidden
    }

    static func references(in text: String) -> [(range: NSRange, label: String)] {
        let mask = make(text)
        let regex = try? NSRegularExpression(pattern: #"\[\^([^\]\s]+)\]"#)
        let source = text as NSString
        return (regex?.matches(in: text, range: NSRange(location: 0, length: source.length)) ?? []).compactMap { match in
            guard !mask[match.range.location] else { return nil }
            return (match.range, source.substring(with: match.range(at: 1)))
        }
    }

    private static func run(_ character: UInt16, from start: Int, in text: [UInt16]) -> Int {
        var end = start
        while end < text.count && text[end] == character { end += 1 }
        return end - start
    }

    private static func starts(_ prefix: [UInt16], at start: Int, in text: [UInt16]) -> Bool {
        start + prefix.count <= text.count && Array(text[start..<(start + prefix.count)]) == prefix
    }

    private static func mark(_ range: Range<Int>, in mask: inout [Bool]) {
        for index in range { mask[index] = true }
    }

}
