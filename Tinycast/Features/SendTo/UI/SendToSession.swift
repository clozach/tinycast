import Foundation
import Observation

@MainActor @Observable
final class SendToSession {
    let payload: SendToPayload
    let source: String
    let targets: [SendToTarget]
    var query = "" {
        didSet { selection = 0 }
    }
    var selection = 0

    init(payload: SendToPayload, source: String, targets: [SendToTarget]) {
        self.payload = payload
        self.source = source
        self.targets = targets
    }

    var matches: [SendToTarget] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty ? targets : targets.filter { $0.name.localizedStandardContains(needle) }
    }

    var selected: SendToTarget? {
        let rows = matches
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func move(_ delta: Int) {
        guard !matches.isEmpty else { return }
        selection = (selection + delta + matches.count) % matches.count
    }
}
