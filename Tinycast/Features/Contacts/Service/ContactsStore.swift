import Contacts
import Foundation

/// The address book, read off the main actor and held in memory; re-read when Contacts changes.
@MainActor
@Observable
final class ContactsStore {
    private(set) var cards: [ContactCard] = []
    private(set) var access: ContactsAccess = Permissions.contactsAccess()
    @ObservationIgnored private var changeObserver: NotificationToken?

    /// Called on every open: TCC sends nothing when a grant changes, so access is read again.
    func prepare() {
        access = Permissions.contactsAccess()
        observeChanges()
        switch access {
        case .granted:
            if cards.isEmpty { reload() }
        case .notDetermined:
            Task {
                _ = await Permissions.requestContactsAccess()
                access = Permissions.contactsAccess()
                if access == .granted { reload() }
            }
        case .denied:
            cards = []
        }
    }

    func card(id: String?) -> ContactCard? {
        guard let id else { return nil }
        return cards.first { $0.id == id }
    }

    private func reload() {
        Task {
            let cards = await Task.detached(priority: .userInitiated) { Self.fetchAll() }.value
            self.cards = cards
        }
    }

    private func observeChanges() {
        guard changeObserver == nil else { return }
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: .CNContactStoreDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.access == .granted else { return }
                self.reload()
            }
        }
        changeObserver = NotificationToken(token, center: center)
    }

    private nonisolated static func keys() -> [any CNKeyDescriptor] {
        [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactTypeKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor,
        CNContactUrlAddressesKey as CNKeyDescriptor,
        CNContactBirthdayKey as CNKeyDescriptor,
        ]
    }

    private nonisolated static func fetchAll() -> [ContactCard] {
        let request = CNContactFetchRequest(keysToFetch: keys())
        request.sortOrder = .userDefault
        var cards: [ContactCard] = []
        try? CNContactStore().enumerateContacts(with: request) { contact, _ in
            if let card = card(from: contact) { cards.append(card) }
        }
        return cards
    }

    private nonisolated static func card(from contact: CNContact) -> ContactCard? {
        let organization = contact.organizationName
        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? organization
        guard !name.isEmpty else { return nil }
        var fields: [ContactField] = []
        func add(_ kind: ContactField.Kind, _ label: String?, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            fields.append(
                ContactField(kind: kind, label: title(label, kind), value: trimmed, position: fields.count))
        }
        for phone in contact.phoneNumbers { add(.phone, phone.label, phone.value.stringValue) }
        for email in contact.emailAddresses { add(.email, email.label, email.value as String) }
        for address in contact.postalAddresses {
            let lines = CNPostalAddressFormatter.string(from: address.value, style: .mailingAddress)
            add(.address, address.label, lines.split(whereSeparator: \.isNewline).joined(separator: ", "))
        }
        for url in contact.urlAddresses { add(.url, url.label, url.value as String) }
        if let birthday = contact.birthday, let text = birthdayText(birthday) {
            add(.birthday, nil, text)
        }
        return ContactCard(
            id: contact.identifier, name: name, organization: organization,
            isCompany: contact.contactType == .organization, fields: fields)
    }

    /// Contacts' label, localized ("mobile", "home"); a field with none is named by its kind.
    private nonisolated static func title(_ label: String?, _ kind: ContactField.Kind) -> String {
        if let label, !label.isEmpty { return CNLabeledValue<NSString>.localizedString(forLabel: label) }
        switch kind {
        case .phone: return "phone"
        case .email: return "email"
        case .address: return "address"
        case .url: return "link"
        case .birthday: return "birthday"
        }
    }

    /// A birthday without a year is still a birthday, so the year is optional in the text.
    private nonisolated static func birthdayText(_ components: DateComponents) -> String? {
        var parts = components
        let hasYear = parts.year != nil
        if !hasYear { parts.year = 2000 }
        guard let date = Calendar(identifier: .gregorian).date(from: parts) else { return nil }
        let style = Date.FormatStyle().month(.wide).day()
        return hasYear ? date.formatted(style.year()) : date.formatted(style)
    }
}
