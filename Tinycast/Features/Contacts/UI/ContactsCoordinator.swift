import AppKit

/// Search Contacts: the card list, a card's fields one press deeper, and what each value does.
@MainActor
final class ContactsCoordinator {
    private let store: ContactsStore
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore

    init(
        store: ContactsStore, palette: PaletteState, paletteCoordinator: PaletteCoordinator,
        core: AppCore
    ) {
        self.store = store
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// The command's shortcut: the list, then the selected card's fields, then closed.
    func runShortcut() {
        if paletteCoordinator.isShowing(.contacts), let card = selectedCard() {
            showFields(of: card)
        } else if paletteCoordinator.isShowing(.contactFields) {
            paletteCoordinator.hidePalette()
        } else {
            show()
        }
    }

    func show() {
        store.prepare()
        paletteCoordinator.togglePalette(mode: .contacts)
    }

    /// Pushed, so Escape returns to the list with its search as it was.
    func showFields(of card: ContactCard) {
        palette.contactID = card.id
        paletteCoordinator.navigate(to: .contactFields)
    }

    func open(_ card: ContactCard) {
        guard let url = URL(string: "addressbook://" + card.id) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.open(url)
    }

    /// ↵ on a field: call a number, write to an address, map a place, open a link; else copy.
    func run(_ field: ContactField) {
        guard let url = Self.url(for: field) else { return copy(field.value) }
        paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.open(url)
    }

    /// Messages takes a number or an email address alike.
    func message(_ field: ContactField) {
        guard let url = URL(string: "sms:" + field.value.filter { !$0.isWhitespace }) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.open(url)
    }

    func copy(_ text: String) {
        paletteCoordinator.hidePalette()
        Paster.copyPlainText(text)
        core.showMessage("Copied \(text)")
    }

    static func verb(for field: ContactField) -> String {
        switch field.kind {
        case .phone: return "Call"
        case .email: return "Write Email"
        case .address: return "Show in Maps"
        case .url: return "Open Link"
        case .birthday: return "Copy"
        }
    }

    static func url(for field: ContactField) -> URL? {
        switch field.kind {
        case .phone:
            return URL(string: "tel:" + field.value.filter { $0.isNumber || $0 == "+" })
        case .email:
            return URL(string: "mailto:" + field.value)
        case .address:
            let query = field.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            return query.flatMap { URL(string: "maps://?q=" + $0) }
        case .url:
            let link = field.value.contains("://") ? field.value : "https://" + field.value
            return URL(string: link)
        case .birthday:
            return nil
        }
    }

    private func selectedCard() -> ContactCard? {
        let rows = ContactSearch.rank(store.cards, query: palette.query)
        return rows.indices.contains(palette.selection) ? rows[palette.selection] : nil
    }
}
