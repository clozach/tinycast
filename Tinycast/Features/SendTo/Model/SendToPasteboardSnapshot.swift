import Foundation

struct SendToPasteboardSnapshot: Equatable, Sendable {
    let items: [[String: Data]]
    let openItems: [URL]
    let displayTitle: String
}
