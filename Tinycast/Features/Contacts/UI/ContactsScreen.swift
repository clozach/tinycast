import SwiftUI

/// Search Contacts: every card, ranked by the query. ↵ opens it in Contacts; ⌘I lists its fields.
struct ContactsScreen: PaletteScreen {
    let store: ContactsStore
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [ContactCard] { ContactSearch.rank(store.cards, query: vm.query) }

    var primaryActionTitle: String { "Open in Contacts" }

    private func card(at selection: Int) -> ContactCard? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let card = card(at: selection) else { return nil }
        let contacts = core.contactsCoordinator
        return PopoverMenuContent(
            header: card.name,
            items: [
                PopoverMenuItem(title: "Open in Contacts", systemImage: "person.crop.circle", shortcut: "↵") {
                    contacts.open(card)
                },
                PopoverMenuItem(title: "Show Fields", systemImage: "list.bullet", shortcut: "⌘I") {
                    contacts.showFields(of: card)
                },
                PopoverMenuItem(title: "Copy Name", systemImage: "doc.on.doc", shortcut: "⌘↵") {
                    contacts.copy(card.name)
                },
            ])
    }

    func activate(at selection: Int) {
        guard let card = card(at: selection) else { return }
        core.contactsCoordinator.open(card)
    }

    func secondary(at selection: Int) -> Bool {
        guard let card = card(at: selection) else { return false }
        core.contactsCoordinator.copy(card.name)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard shortcut == .showDetails, let card = card(at: selection) else { return false }
        core.contactsCoordinator.showFields(of: card)
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        let rows = rows
        guard !rows.isEmpty else { return AnyView(EmptyResults(text: emptyMessage)) }
        return AnyView(
            ContactList(
                title: nil,
                items: rows.map {
                    ContactList.Item(
                        id: $0.id, symbol: $0.isCompany ? "building.2" : "person.crop.circle",
                        title: $0.name, detail: $0.subtitle, trailing: nil)
                },
                selectedID: card(at: selection)?.id, scroll: scroll,
                onActivate: { activate(at: $0) },
                onActions: {
                    vm.selection = $0
                    openActions()
                }))
    }

    /// No access reads very differently from no match, so the empty list says which.
    private var emptyMessage: String {
        switch store.access {
        case .denied: return "Tinycast has no access to your contacts"
        case .notDetermined: return "Waiting for access to your contacts"
        case .granted:
            return vm.query.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Reading your contacts…" : "No matching contacts"
        }
    }
}

/// One card's phones, emails, addresses, links and birthday, filtered by the query.
struct ContactFieldsScreen: PaletteScreen {
    let store: ContactsStore
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    private var card: ContactCard? { store.card(id: vm.contactID) }

    var rows: [ContactField] { ContactSearch.filter(card?.fields ?? [], query: vm.query) }

    var primaryActionTitle: String {
        field(at: vm.selection).map(ContactsCoordinator.verb) ?? "Copy"
    }

    private func field(at selection: Int) -> ContactField? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let card, let field = field(at: selection) else { return nil }
        let contacts = core.contactsCoordinator
        var items = [
            PopoverMenuItem(
                title: ContactsCoordinator.verb(for: field), systemImage: Self.symbol(field.kind),
                shortcut: "↵"
            ) { contacts.run(field) },
            PopoverMenuItem(title: "Copy \(field.label.capitalized)", systemImage: "doc.on.doc", shortcut: "⌘↵") {
                contacts.copy(field.value)
            },
        ]
        if field.kind == .phone || field.kind == .email {
            items.append(PopoverMenuItem(title: "Send Message", systemImage: "message") { contacts.message(field) })
        }
        items.append(
            PopoverMenuItem(title: "Open in Contacts", systemImage: "person.crop.circle", startsSection: true) {
                contacts.open(card)
            })
        return PopoverMenuContent(header: card.name, items: items)
    }

    func activate(at selection: Int) {
        guard let field = field(at: selection) else { return }
        core.contactsCoordinator.run(field)
    }

    func secondary(at selection: Int) -> Bool {
        guard let field = field(at: selection) else { return false }
        core.contactsCoordinator.copy(field.value)
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        let rows = rows
        guard let card else { return AnyView(EmptyResults(text: "That contact is gone")) }
        guard !rows.isEmpty else {
            return AnyView(EmptyResults(text: card.fields.isEmpty ? "No details on this card" : "No matching details"))
        }
        return AnyView(
            ContactList(
                title: card.name,
                items: rows.map {
                    ContactList.Item(
                        id: $0.id, symbol: Self.symbol($0.kind), title: $0.value, detail: nil,
                        trailing: $0.label)
                },
                selectedID: field(at: selection)?.id, scroll: scroll,
                onActivate: { activate(at: $0) },
                onActions: {
                    vm.selection = $0
                    openActions()
                }))
    }

    static func symbol(_ kind: ContactField.Kind) -> String {
        switch kind {
        case .phone: return "phone"
        case .email: return "envelope"
        case .address: return "map"
        case .url: return "link"
        case .birthday: return "gift"
        }
    }
}
