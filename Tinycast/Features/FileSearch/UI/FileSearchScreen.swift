import SwiftUI

struct FileSearchScreen: PaletteScreen {
    let session: FileSearchSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }

    var rows: [FileSearchResult] { session.results }

    private var isShowingRecents: Bool {
        vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var indexer: FileIndexer { core.fileIndexer }

    var primaryActionTitle: String {
        guard let result = result(at: vm.selection) else { return String(localized: "Open File") }
        return result.isDirectory ? String(localized: "Open Folder") : String(localized: "Open File")
    }

    private func result(at selection: Int) -> FileSearchResult? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    func sendToPayload(at selection: Int) -> SendToPayload? {
        result(at: selection).map { .files([$0.url]) }
    }

    func hasActions(at selection: Int) -> Bool { result(at: selection) != nil }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let result = result(at: selection) else { return nil }
        return FileSearchActionsMenu.content(
            result: result, core: core, target: vm.pasteTarget,
            quickLook: { vm.fileSearchQuickLook = true })
    }

    func activate(at selection: Int) {
        guard let result = result(at: selection) else { return }
        core.fileSearchCoordinator.open(result)
    }

    func secondary(at selection: Int) -> Bool {
        guard let result = result(at: selection) else { return false }
        core.fileSearchCoordinator.showInFinder(result)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard let result = result(at: selection) else { return false }
        if shortcut == .quickLook {
            vm.fileSearchQuickLook.toggle()
            return true
        }
        return FileSearchActionsMenu.perform(shortcut, result: result, core: core)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            VStack(spacing: 0) {
                content(selection: selection, scroll: scroll)
                HStack {
                    if indexer.access == .limited {
                        Text("Searching readable folders. Protected folders need Full Disk Access.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Privacy Settings…") {
                            core.fileSearchCoordinator.openFullDiskAccessSettings()
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .frame(height: 28)
            })
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        if rows.isEmpty {
            emptyState
        } else {
            let selected = result(at: selection)
            HStack(spacing: 0) {
                FileSearchList(
                    title: isShowingRecents ? String(localized: "Recent") : String(localized: "Results"),
                    results: rows,
                    selectedID: selected?.id,
                    scroll: scroll,
                    onSelect: { result in vm.selection = rows.firstIndex(of: result) ?? 0 },
                    onActivate: { core.fileSearchCoordinator.open($0) },
                    onActions: { result in
                        if let index = rows.firstIndex(of: result) { vm.selection = index }
                        openActions()
                    },
                    onDropped: { core.paletteCoordinator.dragLanded() }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(width: Theme.Size.hairline)
                FileSearchPreview(result: selected)
            }
            .overlay {
                if vm.fileSearchQuickLook, let selected {
                    FileSearchQuickLook(result: selected) { vm.fileSearchQuickLook = false }
                }
            }
        }
    }

    /// Nothing is said while a query runs: the rows it replaces would only flash a message.
    @ViewBuilder
    private var emptyState: some View {
        if !indexer.hasIndex, case .building(let items) = indexer.status {
            EmptyResults(
                text: String(localized: "Indexing your search folders…"),
                detail: String(
                    localized: "\(items.formatted()) items so far. Results appear when it finishes."),
                systemImage: "externaldrive")
        } else if !indexer.hasIndex, indexer.status == .failed {
            EmptyResults(
                text: String(localized: "Couldn’t build the file index"),
                detail: String(localized: "Try Rebuild Index in Settings ▸ File Search."),
                systemImage: "exclamationmark.triangle")
        } else if session.state != .ready {
            Color.clear
        } else if isShowingRecents {
            EmptyResults(text: String(localized: "Type to search files and folders"))
        } else {
            EmptyResults(text: vm.fileSearchFilter.emptyMessage)
        }
    }
}

@MainActor
enum FileSearchActionsMenu {
    static func content(
        result: FileSearchResult, core: AppCore, target: PasteTarget?,
        quickLook: (() -> Void)? = nil
    ) -> PopoverMenuContent {
        let coordinator = core.fileSearchCoordinator
        var items = [
            PopoverMenuItem(
                title: result.isDirectory ? String(localized: "Open Folder") : String(localized: "Open File"),
                systemImage: result.isDirectory ? "folder" : "doc", shortcut: "↵"
            ) { coordinator.open(result) },
            PopoverMenuItem(
                title: String(localized: "Show in Finder"), systemImage: "folder", shortcut: "⌘↵"
            ) { coordinator.showInFinder(result) }
        ]
        if let quickLook {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Quick Look"), systemImage: "eye", shortcut: "⌘Y",
                    action: quickLook))
        }
        items += [
            PopoverMenuItem(title: String(localized: "Share…"), systemImage: "square.and.arrow.up") {
                coordinator.share(result)
            },
            PopoverMenuItem(
                title: String(localized: "Copy File"), systemImage: "doc.on.clipboard", startsSection: true,
                shortcut: "⇧⌘C"
            ) { coordinator.copyFile(result) },
            PopoverMenuItem(
                title: target.map { String(localized: "Paste File to \($0.name)") }
                    ?? String(localized: "Paste File"),
                icon: .paste(target, fallback: "doc.on.clipboard"), shortcut: "⇧⌘V"
            ) { coordinator.pasteFile(result) },
            PopoverMenuItem(
                title: String(localized: "Copy Name"), systemImage: "doc.on.clipboard", shortcut: "⌥⌘C"
            ) { coordinator.copyName(result) },
            PopoverMenuItem(
                title: String(localized: "Copy Path"), systemImage: "doc.on.clipboard", shortcut: "⌃⌘C"
            ) { coordinator.copyPath(result) },
            PopoverMenuItem(
                title: String(localized: "Move to Trash"), systemImage: "trash", startsSection: true,
                shortcut: "⌃X", isDestructive: true
            ) { coordinator.trash(result) }
        ]
        return PopoverMenuContent(header: result.name, items: items)
    }

    /// No ⌃⇧X: there is no "all" to trash, only the one row.
    static func perform(_ shortcut: PaletteShortcut, result: FileSearchResult, core: AppCore) -> Bool {
        let coordinator = core.fileSearchCoordinator
        switch shortcut {
        case .copyFile: coordinator.copyFile(result)
        case .copyName: coordinator.copyName(result)
        case .copyPath: coordinator.copyPath(result)
        case .pasteFile: coordinator.pasteFile(result)
        // Trashing is undoable, so it asks nothing first, as the clipboard's delete does.
        case .delete: coordinator.trash(result)
        default: return false
        }
        return true
    }
}
