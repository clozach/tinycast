import Foundation

struct TaughtTarget: Codable, Equatable, Identifiable, Sendable {
    enum Delivery: Codable, Equatable, Sendable {
        case open(application: String?)
        case paste
    }

    let id: UUID
    var name: String
    var text: String
    var delivery: Delivery
    /// Optional presentation name; `name` remains the persisted trigger for older libraries.
    var title: String? = nil

    var entryID: String { "taught:" + id.uuidString.lowercased() }
    var displayTitle: String {
        let value = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? name : value
    }
    var targetPreview: String {
        switch delivery {
        case .open:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .paste:
            let preview = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return String(preview.prefix(160)) + (preview.count > 160 ? "…" : "")
        }
    }
}
