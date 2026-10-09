import Foundation

enum WindowSwitchScope: Equatable, Sendable {
    case all
    case application(id: Int32, name: String, includingHidden: Bool)

    var applicationID: Int32? {
        if case .application(let id, _, _) = self { return id }
        return nil
    }

    var applicationName: String? {
        if case .application(_, let name, _) = self { return name }
        return nil
    }

    var includesHidden: Bool {
        if case .application(_, _, let includingHidden) = self { return includingHidden }
        return true
    }

    func includingHidden(_ included: Bool) -> Self {
        guard case .application(let id, let name, _) = self else { return self }
        return .application(id: id, name: name, includingHidden: included)
    }

    func contains(_ entry: WindowSwitchEntry) -> Bool {
        guard let applicationID else { return true }
        return entry.processID == applicationID
            && (includesHidden || (!entry.isMinimized && !entry.isAppHidden))
    }
}
