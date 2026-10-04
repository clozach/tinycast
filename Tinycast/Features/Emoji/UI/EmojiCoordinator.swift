import AppKit

/// Owns emoji delivery: frequency tallies the base glyph, the configured tone applies at copy time.
@MainActor
final class EmojiCoordinator {
    private let frequentEmoji: FrequentEmojiStore
    private let ranking: LauncherRankingStore
    private let settings: AppSettings
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator

    init(
        frequentEmoji: FrequentEmojiStore,
        ranking: LauncherRankingStore,
        settings: AppSettings,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator
    ) {
        self.frequentEmoji = frequentEmoji
        self.ranking = ranking
        self.settings = settings
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
    }

    func pasteEmoji(_ entry: EmojiEntry, searchQuery: String? = nil) {
        record(entry, searchQuery: searchQuery)
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.pasteString(entry.display(tone: settings.emojiSkinTone), previousApp: previous)
    }

    func copyEmoji(_ entry: EmojiEntry, searchQuery: String? = nil) {
        record(entry, searchQuery: searchQuery)
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyString(entry.display(tone: settings.emojiSkinTone))
    }

    /// The tone a paste uses unless one is chosen for it.
    var defaultTone: EmojiSkinTone { settings.emojiSkinTone }

    func pasteEmojiKeepingWindowOpen(_ entry: EmojiEntry, searchQuery: String? = nil) {
        record(entry, searchQuery: searchQuery)
        windowController.pasteStringKeepingWindowOpen(entry.display(tone: settings.emojiSkinTone))
    }

    func resetRanking(_ entry: EmojiEntry) {
        ranking.reset(itemKey: EmojiSearchProfile.preferenceKey(for: entry))
    }

    private func record(_ entry: EmojiEntry, searchQuery: String?) {
        frequentEmoji.record(entry.glyph)
        ranking.visit(itemKey: EmojiSearchProfile.preferenceKey(for: entry), query: searchQuery)
    }
}
