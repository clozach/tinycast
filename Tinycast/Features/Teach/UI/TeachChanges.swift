import Foundation

/// Each mutation carries its inverse; undo touches only that entry's records.
@MainActor
enum TeachChanges {
    struct Change {
        let message: String
        let undo: () throws -> Void
    }

    static func save(_ session: TeachSession, core: AppCore) throws -> Change {
        let alias = TeachPolicy.trigger(session.trigger)
        let undo: () throws -> Void
        switch session.source {
        case .entry(let entry):
            guard core.appIndex.apps.contains(where: { $0.preferenceKey == entry.preferenceKey }) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let previous = core.aliases.alias(for: entry.preferenceKey) ?? ""
            core.aliases.setAlias(alias, for: entry.preferenceKey)
            undo = { [weak core] in
                guard let core else { return }
                try checkAlias(previous, key: entry.preferenceKey, core: core)
                core.aliases.setAlias(previous, for: entry.preferenceKey)
            }
        case .payload(let previous):
            let title = TeachPolicy.trigger(session.title)
            let target = TaughtTarget(
                id: previous?.id ?? UUID(), name: alias, text: session.target, delivery: session.delivery,
                title: title.isEmpty ? nil : title)
            try core.taughtTargets.save(target)
            core.aliases.setAlias(alias, for: target.entryID)
            session.titleLoader.completeAfterSave(target, store: core.taughtTargets)
            undo = { [weak core] in
                guard let core else { return }
                try checkAlias(session.originalAlias, key: target.entryID, core: core)
                if let previous {
                    try core.taughtTargets.save(previous)
                    core.aliases.setAlias(session.originalAlias, for: target.entryID)
                } else {
                    try core.taughtTargets.remove(id: target.id)
                    removeReferences([target.entryID], core: core)
                }
            }
        }
        return Change(message: "Tinycast learned “\(alias)”", undo: undo)
    }

    static func delete(_ target: TaughtTarget, core: AppCore) throws -> Change {
        let key = target.entryID
        let alias = core.aliases.alias(for: key) ?? ""
        let favoriteIndex = core.favorites.keys.firstIndex(of: key)
        let hidden = core.visibility.hiddenItemKeys.contains(key)
        let visit = core.launcherRanking.visits[key]
        try core.taughtTargets.remove(id: target.id)
        removeReferences([key], core: core)
        return Change(message: "Deleted “\(target.displayTitle)”") { [weak core] in
            guard let core else { return }
            try checkAlias(alias, key: key, core: core)
            try core.taughtTargets.save(target)
            core.aliases.setAlias(alias, for: key)
            if let favoriteIndex, !core.favorites.keys.contains(key) {
                var keys = core.favorites.keys
                keys.insert(key, at: min(favoriteIndex, keys.count))
                core.favorites.replace(keys: keys)
            }
            if hidden {
                core.visibility.replace(
                    hiddenItems: Array(core.visibility.hiddenItemKeys.union([key])),
                    disabledKinds: Array(core.visibility.disabledKinds))
            }
            if let visit {
                var visits = core.launcherRanking.visits
                visits[key] = visit
                core.launcherRanking.replace(visits)
            }
        }
    }

    static func removeReferences(_ keys: Set<String>, core: AppCore) {
        core.aliases.removeKeys(keys)
        core.favorites.remove(keys: keys)
        core.visibility.removeItemKeys(keys)
        for key in keys { core.launcherRanking.reset(itemKey: key) }
    }

    private static func checkAlias(_ alias: String, key: String, core: AppCore) throws {
        guard !alias.isEmpty else { return }
        if TeachPolicy.conflict(alias, aliases: core.aliases.aliases, excluding: key) != nil {
            throw UndoFailure.triggerTaken
        }
    }

    private enum UndoFailure: LocalizedError {
        case triggerTaken

        var errorDescription: String? {
            "That trigger now belongs to another item. Change its alias first, then try Undo again."
        }
    }
}
