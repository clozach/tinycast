import AppKit

/// Owns emoji delivery: frequency tallies the base glyph, the configured tone applies at copy time.
@MainActor
final class EmojiCoordinator {
    private let frequentEmoji: FrequentEmojiStore
    private let settings: AppSettings
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator

    init(
        frequentEmoji: FrequentEmojiStore,
        settings: AppSettings,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator
    ) {
        self.frequentEmoji = frequentEmoji
        self.settings = settings
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
    }

    func pasteEmoji(_ entry: EmojiEntry) {
        pasteEmoji(entry, tone: settings.emojiSkinTone)
    }

    /// One tone for this paste; `makeDefault` makes it the tone every later paste uses too.
    func pasteEmoji(_ entry: EmojiEntry, tone: EmojiSkinTone, makeDefault: Bool = false) {
        if makeDefault { settings.emojiSkinTone = tone }
        frequentEmoji.record(entry.glyph)
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.pasteString(entry.display(tone: tone), previousApp: previous)
    }

    func copyEmoji(_ entry: EmojiEntry) {
        copyEmoji(entry, tone: settings.emojiSkinTone)
    }

    func copyEmoji(_ entry: EmojiEntry, tone: EmojiSkinTone) {
        frequentEmoji.record(entry.glyph)
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyString(entry.display(tone: tone))
    }

    /// The tone a paste uses unless one is chosen for it.
    var defaultTone: EmojiSkinTone { settings.emojiSkinTone }

    func pasteEmojiKeepingWindowOpen(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        windowController.pasteStringKeepingWindowOpen(entry.display(tone: settings.emojiSkinTone))
    }
}
