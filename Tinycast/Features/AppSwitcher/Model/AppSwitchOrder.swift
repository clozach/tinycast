import Foundation

enum AppSwitchOrder {
    static func sorted(
        _ entries: [AppSwitchEntry], recentIDs: [Int32], initialID: Int32?
    ) -> [AppSwitchEntry] {
        var remaining = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered: [AppSwitchEntry] = []
        for id in [initialID].compactMap({ $0 }) + recentIDs {
            if let entry = remaining.removeValue(forKey: id) { ordered.append(entry) }
        }
        ordered += remaining.values.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
        if ordered.count > 1 { ordered.swapAt(0, 1) }
        return ordered
    }

    static func next(from selection: Int, count: Int, backwards: Bool) -> Int? {
        guard count > 0 else { return nil }
        let current = min(max(selection, 0), count - 1)
        return (current + (backwards ? count - 1 : 1)) % count
    }

    static func filtered(_ entries: [AppSwitchEntry], query: String) -> [AppSwitchEntry] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return entries.filter { entry in terms.allSatisfy { entry.name.localizedStandardContains($0) } }
    }
}
