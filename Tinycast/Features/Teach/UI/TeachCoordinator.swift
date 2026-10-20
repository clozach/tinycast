import AppKit

@MainActor @Observable
final class TeachCoordinator {
    private unowned let core: AppCore
    private let windowController: PaletteWindowController
    private let sources = NSMapTable<NSWindow, TeachSource.SourceView>.weakToWeakObjects()
    private var task: Task<Void, Never>?
    private var opening: Task<Void, Never>?
    private var pendingUndo: TeachChanges.Change?

    init(core: AppCore, windowController: PaletteWindowController) {
        self.core = core
        self.windowController = windowController
    }

    isolated deinit { task?.cancel(); opening?.cancel() }

    var shortcut: String? { core.hotKeys.binding(for: .command(.teach))?.keycaps.joined() }
    var canUndo: Bool { pendingUndo != nil }

    static func canTeach(_ entry: AppEntry) -> Bool {
        !CommandCatalog.isQueryDriven(entry) && entry.id != CommandID.teach.rawValue && entry.kind != .meeting
    }

    func start() {
        core.taughtTargets.onChange = { [weak self] in self?.publish() }
        publish()
    }

    private func publish() { core.appIndex.setTaughtTargets(core.taughtTargets.targets) }

    func register(_ source: TeachSource.SourceView, in window: NSWindow) {
        sources.setObject(source, forKey: window)
    }

    func request(entry: AppEntry? = nil, contextual: Bool = false) {
        guard task == nil, !core.isShowingDialog else { return }
        let keyWindow = NSApp.keyWindow
        let parent = keyWindow?.parent ?? keyWindow
        let selected = entry ?? (
            contextual && core.palette.isVisible
                ? parent.flatMap { sources.object(forKey: $0)?.entry?() } : nil)
        let source: TeachSession.Source
        if let selected, Self.canTeach(selected) {
            if let payload = core.taughtTargets.target(entryID: selected.id) {
                source = .payload(payload)
            } else {
                source = .entry(selected)
            }
        } else {
            source = .payload(nil)
        }
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        let session = TeachSession(source: source, clipboard: clipboard, aliases: core.aliases, appIndex: core.appIndex)
        refreshApplications(session)
        if session.isPayload { session.titleLoader.refresh(target: session.target) }
        task = Task { [weak self, weak parent] in
            guard let self else { return }
            defer {
                task = nil
                if parent?.isKeyWindow == true, core.palette.isVisible {
                    core.palette.focusToken = UUID()
                }
            }
            await edit(session, parent: parent)
        }
    }

    func edit(_ target: TaughtTarget) {
        let entry = core.appIndex.apps.first { $0.id == target.entryID }
        request(entry: entry)
    }

    private func edit(_ session: TeachSession, parent: NSWindow?) async {
        while !Task.isCancelled {
            let choice = await core.editTeach(session, parent: parent) { [weak self] in
                self?.refreshApplications(session)
            }
            guard choice != 1 else { session.titleLoader.cancel(); return }
            do {
                if choice == 2 { session.titleLoader.cancel(); try await delete(session); return }
                guard session.issue == nil else { continue }
                remember(try TeachChanges.save(session, core: core))
                return
            } catch {
                session.failure = error.localizedDescription
            }
        }
    }

    private func remember(_ change: TeachChanges.Change) {
        pendingUndo = change
        core.showUndo(change.message) { [weak self] in self?.undo() }
    }

    func undo() {
        guard let pendingUndo else { return }
        do {
            try pendingUndo.undo()
            self.pendingUndo = nil
            core.showMessage("Teaching undone")
        } catch { core.showMessage(error.localizedDescription, tone: .danger) }
    }

    private func delete(_ session: TeachSession) async throws {
        guard case .payload(let target?) = session.source else { return }
        guard await core.confirm(
            title: "Delete “\(target.name)”?", message: "The saved target and trigger will be removed.",
            symbol: "trash", confirmTitle: "Delete")
        else { return }
        remember(try TeachChanges.delete(target, core: core))
    }

    func replaceTargets(_ targets: [TaughtTarget]) throws {
        let removed = Set(core.taughtTargets.targets.map(\.entryID)).subtracting(targets.map(\.entryID))
        try core.taughtTargets.replace(targets)
        TeachChanges.removeReferences(removed, core: core)
        pendingUndo = nil
    }

    func activate(entryID: String) {
        guard let target = core.taughtTargets.target(entryID: entryID) else { return }
        let destination = windowController.previousTarget
        if target.delivery == .paste, destination == nil {
            core.showMessage("Focus a text field, then invoke this trigger again.", tone: .danger)
            return
        }
        core.paletteCoordinator.hidePalette(restoreFocus: destination?.ownEditor != nil)
        switch target.delivery {
        case .paste:
            core.textInjector.deliver(
                InjectedText(target.text), target: destination, expectedKeyword: nil,
                keywordLength: 0, automaticGeneration: nil,
                onFailed: { [weak self] in
                    self?.core.showMessage("Couldn’t paste. Focus a text field and try again.", tone: .danger)
                })
        case .open(let application):
            opening?.cancel()
            opening = Task { [weak self] in
                do {
                    try await QuicklinkLauncher.open(
                        target.text, openWithBundleID: application, inNewWindow: false)
                } catch {
                    self?.core.showMessage(error.localizedDescription, tone: .danger)
                }
            }
        }
    }

    private func refreshApplications(_ session: TeachSession) {
        guard session.isPayload, let destination = TeachPolicy.openDestination(session.target) else {
            session.applications = []
            return
        }
        let url: URL
        switch destination {
        case .path(let path): url = URL(fileURLWithPath: path)
        case .web(let value), .network(let value), .deeplink(let value): url = value
        }
        var seen = Set<String>()
        session.applications = NSWorkspace.shared.urlsForApplications(toOpen: url).compactMap { url in
            guard let id = Bundle(url: url)?.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return TeachSession.Application(id: id, name: FileManager.default.displayName(atPath: url.path))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !session.application.isEmpty, !session.applications.contains(where: { $0.id == session.application }) {
            session.applications.append(.init(id: session.application, name: "Unavailable app — choose Default"))
        }
    }
}
