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

    /// The windows of apps that are playing, ready to scan off the main actor.
    func audioTargets(playing: Set<pid_t>) -> [WindowAudioTarget] {
        snapshot.compactMap { entry -> WindowAudioTarget? in
            guard playing.contains(entry.processID), let element = elements[entry.handle] else { return nil }
            return WindowAudioTarget(handle: entry.handle, processID: entry.processID, window: element.window)
        }
    }

    func applyAudio(_ audio: [Int: AudioPlayback]) {
        let next = snapshot.map { entry -> WindowSwitchEntry in
            var entry = entry
            entry.audio = audio[entry.handle] ?? .silent
            return entry
        }
        guard next != snapshot else { return }
        snapshot = next
        applyQuery()
    }

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
