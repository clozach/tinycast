import Foundation

enum SendToPayload: Equatable, Sendable {
    case text(String)
    case files([URL])
    case image(URL)
    case pasteboard(SendToPasteboardSnapshot)

    var displayTitle: String {
        switch self {
        case .text(let value):
            let line = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first
            return line.map { String($0.prefix(100)) } ?? "Text"
        case .files(let urls): return urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        case .image(let url): return url.lastPathComponent
        case .pasteboard(let snapshot): return snapshot.displayTitle
        }
    }

    var openItems: [URL] {
        switch self {
        case .text(let value): return Self.link(in: value).map { [$0] } ?? []
        case .files(let urls): return urls
        case .image(let url): return [url]
        case .pasteboard(let snapshot): return snapshot.openItems
        }
    }

    static func link(in value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
              let scheme = url.scheme, scheme.count > 1 else { return nil }
        if ["http", "https"].contains(scheme.lowercased()), url.host?.isEmpty != false { return nil }
        return url
    }
}
