import Foundation

@main
@MainActor
struct WindowSwitchTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func entry(
        _ handle: Int, app: String = "Safari", title: String = "Window",
        minimized: Bool = false, rank: Int = 0
    ) -> WindowSwitchEntry {
        WindowSwitchEntry(
            handle: handle, appName: app, bundleID: "com.example.\(app.lowercased())",
            iconURL: nil, iconStamp: 0, title: title, isMinimized: minimized, appRank: rank)
    }

    static func main() {
        identity()
        displayTitle()
        searchMapping()
        ordering()
        orderingIsTotal()
        ranking()
        rankingLimit()
        applicationScope()
        restorableDialogs()

        print(failures == 0 ? "Window switch tests passed" : "\(failures) window switch tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func identity() {
        expect(entry(7).id == "7", "the id is the handle, which is unique inside one sweep")
    }

    static func restorableDialogs() {
        expect(WindowSwitchEligibility.includes(isStandard: true, isDialog: false, canMinimize: false),
            "standard windows remain eligible even when minimization is unavailable")
        expect(WindowSwitchEligibility.includes(isStandard: false, isDialog: true, canMinimize: true),
            "TextEdit's minimizable document dialogs are switchable")
        expect(!WindowSwitchEligibility.includes(isStandard: false, isDialog: true, canMinimize: false),
            "transient dialog menus stay out")
        expect(!WindowSwitchEligibility.includes(isStandard: false, isDialog: false, canMinimize: true),
            "floating and helper panels stay out")
    }

    static func applicationScope() {
        let visible = WindowSwitchEntry(handle: 0, appName: "Editor", bundleID: "test",
            iconURL: nil, iconStamp: 0, title: "Draft", isMinimized: false, appRank: 0, processID: 42)
        let minimized = WindowSwitchEntry(handle: 1, appName: "Editor", bundleID: "test",
            iconURL: nil, iconStamp: 0, title: "Archive", isMinimized: true, appRank: 0, processID: 42)
        var hidden = visible
        hidden.isAppHidden = true
        var otherProcess = visible
        otherProcess.processID = 43
        let scope = WindowSwitchScope.application(id: 42, name: "Editor", includingHidden: false)
        expect(scope.contains(visible), "visible windows belong to the selected process")
        expect(!scope.contains(minimized), "minimized windows stay out until Option is held")
        expect(!scope.contains(hidden), "hidden app windows stay out until Option is held")
        expect(!scope.contains(otherProcess), "another instance of the same app stays out")
        let expanded = scope.includingHidden(true)
        expect(expanded.contains(minimized) && expanded.contains(hidden), "Option includes both kinds")
        expect(!expanded.contains(otherProcess), "Option never expands to another app")
        expect(expanded.includingHidden(false) == scope, "releasing Option returns to visible scope")
        expect(WindowSwitchScope.all.includingHidden(false) == .all, "global switcher retains all windows")
        expect(WindowSwitchScope.all.contains(minimized), "global switcher still includes minimized windows")
        expect(WindowSwitchQuery.rank([visible, minimized].filter(expanded.contains), for: "arch")
            .map(\.handle) == [1], "typing finds a minimized title when expanded")
        expect(WindowSwitchQuery.rank([visible, minimized].filter(scope.contains), for: "arch").isEmpty,
            "the same query cannot leak a minimized window when narrowed")
    }

    static func displayTitle() {
        expect(entry(0, title: "Notes.md").displayTitle == "Notes.md", "a titled window shows it")
        expect(
            entry(0, app: "Preview", title: "").displayTitle == "Preview",
            "an untitled window reads as its app rather than as a blank row")
        expect(
            entry(0, app: "Preview", title: "   ").displayTitle == "Preview",
            "a whitespace-only title is no title")
    }

    static func searchMapping() {
        let aliases = entry(0, app: "Safari", title: "Inbox").searchFields().aliases
        expect(
            aliases.contains { $0.text == "Inbox" && $0.role == .name },
            "the window title is the name a query matches")
        expect(
            aliases.contains { $0.text == "Safari" && $0.role == .owner },
            "the app rides as owner: every window of one app shares it")
    }

    static func ordering() {
        let sorted = WindowSwitchOrder.sorted([
            entry(0, app: "Mail", rank: 2),
            entry(1, app: "Safari", minimized: true, rank: 0),
            entry(2, app: "Safari", rank: 0),
            entry(3, app: "Safari", rank: 0),
            entry(4, app: "Zed", rank: .max)
        ])
        expect(
            sorted.map(\.handle) == [2, 3, 0, 4, 1],
            "front app first, then by rank, unranked next, minimized last: \(sorted.map(\.handle))")
    }

    static func orderingIsTotal() {
        let entries = (0..<12).map {
            entry($0, app: ["Mail", "Safari", "Zed"][$0 % 3], minimized: $0 % 4 == 0, rank: $0 % 3)
        }
        let once = WindowSwitchOrder.sorted(entries)
        let twice = WindowSwitchOrder.sorted(entries.reversed())
        expect(
            once.map(\.handle) == twice.map(\.handle),
            "the order is total, so a shuffled sweep sorts identically")
        expect(
            once.map(\.handle).sorted() == entries.map(\.handle).sorted(),
            "sorting drops nothing")
        let split = once.firstIndex(where: \.isMinimized) ?? once.count
        expect(
            once[split...].allSatisfy(\.isMinimized),
            "minimized windows form one run at the end, never interleaved")
    }

    static func ranking() {
        let entries = [
            entry(0, app: "Mail", title: "Drafts"),
            entry(1, app: "Safari", title: "Inbox"),
            entry(2, app: "Safari", title: "Inbox archive")
        ]
        expect(
            WindowSwitchQuery.rank(entries, for: "").map(\.handle) == [0, 1, 2],
            "an empty query keeps the order it was handed")
        expect(
            WindowSwitchQuery.rank(entries, for: "Inbox").first?.handle == 1,
            "the exact title beats the one that only starts with it")
        expect(
            WindowSwitchQuery.rank(entries, for: "Safari").map(\.handle) == [1, 2],
            "the app name matches every one of its windows, in the order given")
        expect(
            WindowSwitchQuery.rank(entries, for: "zzz").isEmpty,
            "a query nothing matches ranks nothing")
    }

    static func rankingLimit() {
        let entries = (0..<(WindowSwitchQuery.resultLimit + 50)).map {
            entry($0, app: "Safari", title: "Tab \($0)")
        }
        expect(
            WindowSwitchQuery.rank(entries, for: "").count == WindowSwitchQuery.resultLimit,
            "an empty query is capped too, so a huge sweep never builds a huge list")
        expect(
            WindowSwitchQuery.rank(entries, for: "Tab").count == WindowSwitchQuery.resultLimit,
            "the cap holds under a query every row matches")
    }
}
