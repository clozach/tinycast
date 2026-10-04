import Foundation

/// One card from Contacts, flattened to what the palette searches and shows.
struct ContactCard: Identifiable, Hashable, Sendable {
    /// `CNContact.identifier`, which is also what `addressbook://` opens.
    let id: String
    let name: String
    let organization: String
    let isCompany: Bool
    let fields: [ContactField]

    /// The row's second line: the company when it isn't already the name, else the first value.
    var subtitle: String? {
        if !organization.isEmpty, organization != name { return organization }
        return fields.first { $0.kind == .email || $0.kind == .phone }?.value
    }
}

/// One value on a card, in the order Contacts lists them.
struct ContactField: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case phone, email, address, url, birthday
    }

    let kind: Kind
    /// Contacts' own label, localized: "mobile", "home", "work".
    let label: String
    let value: String
    /// Position on the card, so two numbers with the same label stay distinct.
    let position: Int

    var id: String { "\(kind.rawValue)-\(position)" }
}
