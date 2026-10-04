import Foundation

enum LauncherSearchResult: Identifiable, Equatable, Sendable {
    case entry(AppEntry)
    case emoji(EmojiEntry)

    var id: String {
        switch self {
        case .entry(let entry): entry.id
        case .emoji(let entry): EmojiSearchProfile.preferenceKey(for: entry)
        }
    }
}
