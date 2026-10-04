import Foundation

/// The card last acted on and the search that found it, offered back to a reopened Search Contacts.
struct ContactRecall: Equatable, Sendable {
    let cardID: String
    let name: String
    /// What the list was searching when the card was used; empty when it was picked unsearched.
    let query: String
    let usedAt: Date

    /// The search to reopen on: the one that found the card, else its name. 0 minutes means never.
    func search(at now: Date, minutes: Int) -> String? {
        let elapsed = now.timeIntervalSince(usedAt)
        guard minutes > 0, elapsed >= 0, elapsed < TimeInterval(minutes * 60) else { return nil }
        return reopenedSearch
    }

    /// Where the recalled card sits, while the search still reads what it reopened on.
    func landing(in cards: [ContactCard], query typed: String) -> Int? {
        guard typed == reopenedSearch else { return nil }
        return cards.firstIndex { $0.id == cardID }
    }

    private var reopenedSearch: String { query.isEmpty ? name : query }
}
