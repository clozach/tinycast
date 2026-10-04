import Foundation

/// Ranks cards: a name hit beats a company hit beats an email or number; subsequences are noise.
enum ContactSearch {
    static func rank(_ cards: [ContactCard], query: String) -> [ContactCard] {
        let typed = query.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return cards.sorted(by: alphabetical) }
        let needle = Needle(typed)
        return
            cards
            .compactMap { card in score(card, needle).map { (card, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : alphabetical($0.0, $1.0) }
            .map(\.0)
    }

    /// A card's fields that the query names, by value or by label.
    static func filter(_ fields: [ContactField], query: String) -> [ContactField] {
        let typed = query.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return fields }
        let needle = FuzzyMatch.Query(typed)
        let digits = typed.filter(\.isNumber)
        return fields.filter {
            hit(needle, $0.value) != nil || hit(needle, $0.label) != nil
                || ($0.kind == .phone && matchesDigits(digits, in: $0.value))
        }
    }

    private static let nameWeight = 3_000_000
    private static let companyWeight = 2_000_000
    private static let valueWeight = 1_000_000

    /// The query three ways: as typed, without apostrophes, and as its digits.
    private struct Needle {
        let typed: FuzzyMatch.Query
        let bare: FuzzyMatch.Query
        let digits: String

        init(_ text: String) {
            typed = FuzzyMatch.Query(text)
            bare = FuzzyMatch.Query(ContactSearch.withoutApostrophes(text))
            digits = text.filter(\.isNumber)
        }
    }

    private static func score(_ card: ContactCard, _ needle: Needle) -> Int? {
        if let score = nameHit(needle, card.name) { return nameWeight + score }
        if let score = nameHit(needle, card.organization) { return companyWeight + score }
        for field in card.fields where field.kind == .email || field.kind == .phone {
            if let score = hit(needle.typed, field.value) { return valueWeight + score }
            if field.kind == .phone, matchesDigits(needle.digits, in: field.value) { return valueWeight }
        }
        return nil
    }

    /// `lozach` finds Lozac'h and `obrien` O'Brien; `brien` still starts a word of O'Brien.
    private static func nameHit(_ needle: Needle, _ name: String) -> Int? {
        [hit(needle.typed, name), hit(needle.bare, withoutApostrophes(name))].compactMap { $0 }.max()
    }

    private static func withoutApostrophes(_ text: String) -> String {
        text.filter { $0 != "'" && $0 != "\u{2019}" && $0 != "\u{02BC}" }
    }

    private static func hit(_ needle: FuzzyMatch.Query, _ text: String) -> Int? {
        guard !text.isEmpty, let match = FuzzyMatch.match(needle, candidate: text) else { return nil }
        return match.tier == .subsequence ? nil : match.score
    }

    /// `5551234` finds (555) 123-4; three digits, so a stray number in a name stays a name.
    private static func matchesDigits(_ digits: String, in number: String) -> Bool {
        digits.count >= 3 && number.filter(\.isNumber).contains(digits)
    }

    private static func alphabetical(_ lhs: ContactCard, _ rhs: ContactCard) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
