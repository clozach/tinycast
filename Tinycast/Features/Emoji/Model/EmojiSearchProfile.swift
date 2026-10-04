import Foundation

enum EmojiSearchProfile {
    static func preferenceKey(for entry: EmojiEntry) -> String { "emoji-" + entry.glyph }

    static func make(_ entry: EmojiEntry) -> SearchProfile {
        let keywords = entry.keywords.split(separator: ",").map(String.init)
        let names = [entry.name] + keywords
        var sources = EntryNaming.Sources(name: entry.name)
        sources.alternateTitles = keywords + [entry.glyph] + names.map { ":" + $0 + ":" }
        return EntryNaming.profile(for: sources)
    }
}
