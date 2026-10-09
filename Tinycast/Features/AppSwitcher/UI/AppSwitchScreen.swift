import SwiftUI

struct AppSwitchScreen: PaletteScreen {
    let coordinator: AppSwitchCoordinator

    var rows: [AppSwitchEntry] { coordinator.filtered }
    var primaryActionTitle: String {
        coordinator.releasesToActivate ? "Release keys to switch" : "Switch to App"
    }
    func hasActions(at selection: Int) -> Bool { rows.indices.contains(selection) }
    func actions(at selection: Int) -> PopoverMenuContent? {
        guard rows.indices.contains(selection) else { return nil }
        return PopoverMenuContent(header: rows[selection].name, items: [
            PopoverMenuItem(title: "Show Windows", systemImage: "macwindow.on.rectangle", shortcut: "→") {
                coordinator.showWindows(at: selection, includingHidden: NSEvent.modifierFlags.contains(.option))
            }
        ])
    }
    func activate(at selection: Int) { coordinator.activate(at: selection) }
    func secondary(at selection: Int) -> Bool { false }
    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(AppSwitchList(
            entries: rows, selection: selection, scroll: scroll,
            onActivate: { coordinator.activate(at: $0) }))
    }
}
