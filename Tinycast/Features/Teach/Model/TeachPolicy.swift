import Foundation

enum TeachPolicy {
    static func trigger(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func conflict(_ trigger: String, aliases: [String: String], excluding key: String?) -> String? {
        let normalized = FuzzyMatch.normalized(Self.trigger(trigger))
        return aliases.keys.sorted().first {
            $0 != key && FuzzyMatch.normalized(Self.trigger(aliases[$0] ?? "")) == normalized
        }
    }

    static func openDestination(_ text: String) -> QuicklinkDestination? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains(where: \.isNewline), let destination = QuicklinkDestination.detect(value)
        else { return nil }
        switch destination {
        case .web(let url):
            guard let host = url.host, !host.isEmpty else { return nil }
        case .deeplink(let url):
            guard !["javascript", "data", "vbscript"].contains(url.scheme?.lowercased() ?? "")
            else { return nil }
        case .network, .path: break
        }
        return destination
    }

    static func validate(_ targets: [TaughtTarget]) throws {
        var ids = Set<UUID>()
        for target in targets {
            guard ids.insert(target.id).inserted, !trigger(target.name).isEmpty,
                !target.name.contains(where: \.isNewline), !trigger(target.text).isEmpty
            else { throw CocoaError(.coderInvalidValue) }
            if target.title?.contains(where: \.isNewline) == true { throw CocoaError(.coderInvalidValue) }
            if case .open = target.delivery, openDestination(target.text) == nil {
                throw CocoaError(.coderInvalidValue)
            }
        }
    }
}
