import Foundation

@main
@MainActor
struct EmojiRootSearchTests {
    static var failures = 0

    struct Candidate {
        let key: String
        let title: String
        let profile: SearchProfile
        let priority: Int
    }

    static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("emoji-root-search-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ranking = LauncherRankingStore(
            fileURL: directory.appendingPathComponent("ranking.json"), now: { now })
        let index = EmojiIndex()
        await index.load("""
            🔖|bookmark|ob|0|mark
            📑|bookmark tabs|ob|0|mark
            🇹🇲|flag: Turkmenistan|fl|0|flag
            ✅|check mark button|sy|0|check
            A|amber heart|sy|0|heart
            B|blue heart|sy|0|heart
            C|cyan heart|sy|0|heart
            D|dark heart|sy|0|heart
            E|emerald heart|sy|0|heart
            Z|zebra heart|sy|0|heart
            👍|thumbs up|sp|1|+1,yes
            🙏|folded hands|sp|1|pray,prayer
            🐱|cat face|an|0|cat,猫,chats
            O|circle|sy|0|red,round
            """)
        let applications = ["Keyboard Maestro", "Keymapp", "Karabiner-Elements", "Pray Timer"]
            .map { name in
                Candidate(
                    key: name, title: name, profile: EntryNaming.profile(for: .init(name: name)),
                    priority: 4)
            }
        let candidates = applications + index.entries.map {
            Candidate(
                key: EmojiSearchProfile.preferenceKey(for: $0), title: $0.displayName,
                profile: index.launcherProfile(for: $0), priority: 0)
        }
        func ranked(_ query: String, limit: Int = 200) -> [String] {
            let usage = ranking.snapshot()
            return LauncherOrder.ranked(
                candidates, query: LauncherOrder.Query(query), sensitivity: .medium, limit: limit,
                profile: \.profile,
                signals: {
                    LauncherOrder.Signals(
                        usage: usage.usage(for: $0.key), priority: $0.priority, title: $0.title)
                }).map(\.key)
        }

        expect(ranked("KM").first == "Keyboard Maestro", "initials compete on the shared score")
        expect(ranked("km").contains("emoji-🔖"), "emoji remain ordinary matching candidates")
        ranking.visit(itemKey: "emoji-🔖", query: "km")
        expect(ranked("km").first == "emoji-🔖", "a chosen emoji learns its root query")
        ranking.visit(itemKey: "Keyboard Maestro", query: "KM")
        ranking.visit(itemKey: "Keyboard Maestro", query: "KM")
        expect(ranked("km").first == "Keyboard Maestro", "repeated app choices overtake emoji")
        expect(ranked("bookmark").first == "emoji-🔖", "an unrelated learned app stays out")

        let hearts = ranked("heart")
        expect(hearts.count == 6, "all matching emoji enter before a result cap")
        expect(hearts.firstIndex(of: "emoji-Z") == 5, "fixture starts beyond the old four-row cap")
        ranking.visit(itemKey: "emoji-Z", query: "heart")
        expect(ranked("heart", limit: 4).first == "emoji-Z", "learning works beyond the old cap")
        ranking.reset(itemKey: "emoji-Z")
        expect(ranked("heart") == hearts, "reset restores the shared textual ordering")

        expect(ranked("pray").first == "emoji-🙏", "CLDR synonyms compete as alternate names")
        expect(ranked(":+1:").first == "emoji-👍", "colon-wrapped aliases survive shared ranking")
        expect(ranked("猫").contains("emoji-🐱"), "localized CLDR terms remain searchable")
        expect(ranked("chats").contains("emoji-🐱"), "localized phrase aliases remain searchable")
        expect(!ranked("rr").contains("emoji-O"), "a match cannot cross keyword boundaries")

        await ranking.flush()
        let reloaded = LauncherRankingStore(
            fileURL: directory.appendingPathComponent("ranking.json"), now: { now })
        expect(
            reloaded.snapshot().usage(for: "emoji-🔖").searchTerms == ["km"],
            "emoji query learning uses the same persisted store")
        await catalogPerformance()
        print("emoji-root-search-test: \(failures == 0 ? "all checks passed" : "failed")")
        exit(failures == 0 ? 0 : 1)
    }

    static func catalogPerformance() async {
        let index = EmojiIndex()
        await index.load()
        let start = ContinuousClock.now
        for query in ["km", "heart", "pray", ":+1:", "face"] {
            _ = LauncherOrder.ranked(
                index.entries, query: LauncherOrder.Query(query), sensitivity: .medium, limit: 200,
                profile: { index.launcherProfile(for: $0) },
                signals: { LauncherOrder.Signals(usage: .unused, priority: 0, title: $0.displayName) })
        }
        print("Full emoji catalog, five root queries: \(start.duration(to: .now))")
    }
}
