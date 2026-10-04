import Foundation

/// The card last acted on, which a reopened Search Contacts offers back for a few minutes.
struct ContactRecall: Equatable, Sendable {
    let cardID: String
    let name: String
    let usedAt: Date

    /// The search to reopen on, or nil once `minutes` have passed; 0 minutes means never.
    func query(at now: Date, minutes: Int) -> String? {
        let elapsed = now.timeIntervalSince(usedAt)
        guard minutes > 0, elapsed >= 0, elapsed < TimeInterval(minutes * 60) else { return nil }
        return name
    }

    /// Where the recalled card sits, while the search still reads its name.
    func landing(in cards: [ContactCard], query: String) -> Int? {
        guard query == name else { return nil }
        return cards.firstIndex { $0.id == cardID }
    }
}
