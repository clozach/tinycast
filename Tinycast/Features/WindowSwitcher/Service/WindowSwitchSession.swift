import Foundation

@MainActor
@Observable
final class WindowSwitchSession {
    private(set) var scope: WindowSwitchScope = .all
    private(set) var snapshot: [WindowSwitchEntry] = []
    /// The rows the list reads: ranked once per query change, so one keystroke ranks once.
    private(set) var filtered: [WindowSwitchEntry] = []

    private var query = ""
    /// Live AX handles, so they are never observed and never outlive the show.
    @ObservationIgnored private var elements: [Int: WindowSwitchSweep.Element] = [:]

    func present(_ snapshot: WindowSwitchSweep.Snapshot, scope: WindowSwitchScope = .all) {
        self.scope = scope
        self.snapshot = WindowSwitchOrder.sorted(snapshot.entries)
        elements = snapshot.elements
        applyQuery()
    }

    func element(for handle: Int) -> WindowSwitchSweep.Element? { elements[handle] }

    func reset() {
        scope = .all
        snapshot = []
        filtered = []
        elements = [:]
        query = ""
    }

    func filter(_ query: String) {
        self.query = query
        applyQuery()
    }

    func includeHidden(_ included: Bool) -> Bool {
        let next = scope.includingHidden(included)
        guard next != scope else { return false }
        scope = next
        applyQuery()
        return true
    }

    private func applyQuery() {
        filtered = WindowSwitchQuery.rank(
            snapshot.filter(scope.contains), for: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
