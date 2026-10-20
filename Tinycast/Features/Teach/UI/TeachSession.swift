import AppKit

@MainActor @Observable
final class TeachSession {
    enum Source {
        case entry(AppEntry)
        case payload(TaughtTarget?)
    }

    struct Application: Identifiable {
        let id: String
        let name: String
    }

    let source: Source
    let originalAlias: String
    var trigger: String
    var target: String
    let titleLoader: TeachTitleLoader
    var title: String {
        get { titleLoader.title }
        set { titleLoader.title = newValue }
    }
    var delivery: TaughtTarget.Delivery
    var applications: [Application] = []
    var failure: String?
    private let aliases: AliasStore
    private let appIndex: AppIndex

    init(source: Source, clipboard: String, aliases: AliasStore, appIndex: AppIndex) {
        self.source = source
        self.aliases = aliases
        self.appIndex = appIndex
        switch source {
        case .entry(let entry):
            originalAlias = aliases.alias(for: entry.preferenceKey) ?? ""
            target = entry.name
            titleLoader = TeachTitleLoader(title: nil)
            delivery = .paste
        case .payload(let payload):
            originalAlias = payload.flatMap { aliases.alias(for: $0.entryID) ?? $0.name } ?? ""
            target = payload?.text ?? clipboard
            titleLoader = TeachTitleLoader(title: payload?.title)
            delivery = payload?.delivery ?? (TeachPolicy.openDestination(clipboard) == nil ? .paste : .open(application: nil))
        }
        trigger = originalAlias
    }

    var entryKey: String? {
        switch source {
        case .entry(let entry): entry.preferenceKey
        case .payload(let payload): payload?.entryID
        }
    }

    var isPayload: Bool { if case .payload = source { true } else { false } }
    var canDelete: Bool { if case .payload(.some) = source { true } else { false } }
    var opens: Bool {
        get { if case .open = delivery { true } else { false } }
        set { delivery = newValue ? .open(application: nil) : .paste }
    }
    var application: String {
        get { if case .open(let app) = delivery { app ?? "" } else { "" } }
        set { delivery = .open(application: newValue.isEmpty ? nil : newValue) }
    }

    var issue: String? {
        let value = TeachPolicy.trigger(trigger)
        if value.isEmpty { return "Enter a trigger to teach Tinycast." }
        if value.contains(where: \.isNewline) { return "Use a single line for the trigger." }
        if let key = TeachPolicy.conflict(value, aliases: aliases.aliases, excluding: entryKey) {
            let name = appIndex.apps.first { $0.preferenceKey == key }?.name ?? "another saved item"
            return "“\(value)” already belongs to \(name). Choose another trigger."
        }
        if isPayload, TeachPolicy.trigger(target).isEmpty { return "Enter or paste a target." }
        if isPayload, title.contains(where: \.isNewline) { return "Use a single line for the title." }
        if isPayload, opens, TeachPolicy.openDestination(target) == nil {
            return "Enter a valid URL or path, or choose Paste for literal text."
        }
        return nil
    }

    var replacement: String {
        guard !originalAlias.isEmpty, TeachPolicy.trigger(trigger) != originalAlias else { return "" }
        return "Replaces “\(originalAlias)”. You can undo after saving."
    }
}
