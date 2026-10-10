import AppKit
import Carbon.HIToolbox

@main @MainActor struct AppWindowTests {
    static var passes = 0
    static var failures = 0
    static func expect(_ value: Bool, _ message: String) {
        if value { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }
    static func key(_ code: Int, flags: NSEvent.ModifierFlags = [], text: String = "", base: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: base,
            isARepeat: false, keyCode: UInt16(code))!
    }
    static func flags(_ value: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: value, timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: UInt16(kVK_Option))!
    }
    static func main() {
        let core = AppCore()
        core.palette.prepare(mode: .launcher)
        core.palette.query = "original"
        core.palette.selection = 3
        core.appSwitchCoordinator.present()
        expect(core.palette.mode == .switchApps, "the shipped presentation enters the app list")
        expect(core.appSwitchCoordinator.filtered.first?.id == 42, "the selected app is the previous app")
        expect(!core.appSwitchCoordinator.handle(key(kVK_RightArrow, flags: .command), atQueryEnd: false),
            "the app gesture leaves right inside the text with the caret")
        expect(core.appSwitchCoordinator.handle(key(kVK_RightArrow, flags: .command)), "right works with Command held")
        expect(core.palette.mode == .switchWindows, "right opens app windows")
        expect(WindowSwitchSweep.lastApplicationID == 42, "the sweep reads only the selected process")
        expect(core.windowSwitch.filtered.map(\.handle) == [0], "default list excludes minimized and hidden windows")
        expect(!core.appSwitchCoordinator.releasesToActivate, "drilling down cancels app release activation")
        _ = core.windowSwitchCoordinator.handle(flags(.option))
        expect(core.windowSwitch.filtered.map(\.handle) == [0, 2, 1], "Option expands both hidden and minimized windows")
        core.palette.selection = 2
        core.palette.query = "archive"
        core.windowSwitch.filter(core.palette.query)
        expect(core.windowSwitch.filtered.map(\.handle) == [1], "typing filters the expanded list")
        _ = core.windowSwitchCoordinator.handle(flags([]))
        expect(core.windowSwitch.filtered.isEmpty && core.palette.selection == 0, "Option release narrows safely")
        expect(core.palette.query == "archive", "Option release preserves the query")
        _ = core.windowSwitchCoordinator.handle(flags(.option))
        expect(core.windowSwitch.filtered.map(\.handle) == [1], "Option press restores matching minimized windows")
        let letter = core.windowSwitchCoordinator.filteringEvent(key(kVK_ANSI_A, flags: .option, text: "å", base: "a"))
        expect(letter?.characters == "a" && letter?.modifierFlags.contains(.option) == false,
            "Option letters type ordinary letters into the filter")
        let deadKey = core.windowSwitchCoordinator.filteringEvent(key(kVK_ANSI_E, flags: .option, base: "e"))
        expect(deadKey?.characters == "e", "Option dead keys filter as letters")
        expect(core.windowSwitchCoordinator.filteringEvent(key(kVK_LeftArrow, flags: .option, base: "\u{F702}")) == nil,
            "Option arrow keeps normal word navigation")
        expect(core.windowSwitchCoordinator.filteringEvent(key(kVK_ANSI_A, flags: [.command, .option], base: "a")) == nil,
            "Command shortcuts are preserved")
        core.palette.menuOpen = true
        expect(core.windowSwitchCoordinator.filteringEvent(key(kVK_ANSI_A, flags: .option, base: "a")) == nil,
            "an open menu retains keyboard ownership")
        core.palette.menuOpen = false
        expect(core.windowSwitchCoordinator.handle(key(kVK_Return, flags: .option)), "Option Return restores a window")
        expect(AXWindowAccess.unminimized == [1], "activation unminimizes the selected window")
        expect(AXWindowAccess.focused == [1], "activation focuses that same window")
        expect(!core.paletteCoordinator.lastRestoreFocus, "activation cannot race the original app")
        expect(core.palette.mode == .launcher && core.palette.query == "original" && core.palette.selection == 3,
            "activation unwinds both temporary screens and restores the original search")
        core.paletteCoordinator.isVisible = true
        core.appSwitchCoordinator.present()
        core.palette.selection = 1
        core.appSwitchCoordinator.showWindows(at: 1)
        core.palette.query = "draft"
        expect(!core.windowSwitchCoordinator.handle(key(kVK_LeftArrow)), "the shared field boundary owns left")
        core.palette.query = ""
        expect(core.palette.pop(preservingScreenState: true), "the shared back step returns to apps")
        expect(core.palette.mode == .switchApps && core.palette.selection == 1, "back preserves the selected app")
        core.palette.query = "editor"
        _ = core.appSwitchCoordinator.queryChanged()
        core.appSwitchCoordinator.showWindows(at: 0)
        core.palette.query = ""
        _ = core.palette.pop(preservingScreenState: true)
        expect(core.palette.query == "editor" && !core.appSwitchCoordinator.queryChanged(),
            "back restores the app query without resetting its selection")
        core.palette.query = ""
        _ = core.appSwitchCoordinator.queryChanged()
        core.windowSwitch.reset()
        core.appSwitchCoordinator.showWindows(at: 0, includingHidden: true)
        expect(core.windowSwitch.scope.includesHidden, "Option may already be held on entry")
        core.windowSwitchCoordinator.show()
        expect(core.windowSwitch.scope == .all, "global window shortcut leaves the scoped list")
        let globalCount = core.windowSwitch.filtered.count
        _ = core.windowSwitchCoordinator.handle(flags([]))
        expect(core.windowSwitch.filtered.count == globalCount, "global window list retains minimized windows")
        core.palette.prepare(mode: .launcher)
        core.palette.query = "saf"
        core.palette.selection = 2
        core.windowSwitchCoordinator.showWindows(of: AppSwitchEntry(id: 42, name: "Safari", bundlePath: nil),
            includingHidden: false)
        core.palette.query = "window"
        expect(core.palette.pop(preservingScreenState: true), "back works while a window filter contains text")
        expect(core.palette.mode == .launcher && core.palette.query == "saf" && core.palette.selection == 2
            && core.palette.restoresSelection, "back restores ordinary search and its highlighted app")
        core.palette.query = "sa"
        expect(!core.palette.restoresSelection, "editing after back resumes normal result landing")
        core.palette.query = "saf"
        core.palette.selection = 2
        core.windowSwitchCoordinator.showWindows(of: AppSwitchEntry(id: 42, name: "Safari", bundlePath: nil),
            includingHidden: true)
        core.paletteCoordinator.hidePalette()
        expect(core.palette.mode == .launcher && core.palette.query == "saf" && core.palette.selection == 2,
            "activation or dismissal restores the ordinary search parent too")
        core.paletteCoordinator.isVisible = true
        expect(!core.windowSwitchCoordinator.showWindows(of: AppEntry(kind: .command, bundleID: "com.apple.Safari",
            name: "Command")), "a command row cannot masquerade as an app")
        expect(!core.windowSwitchCoordinator.showWindows(of: AppEntry(kind: .application, bundleID: "missing.fixture",
            name: "Not running")), "browsing does not launch a stopped app")
        Permissions.allowed = false
        core.palette.mode = .switchApps
        let previousScope = core.windowSwitch.scope
        core.appSwitchCoordinator.showWindows(at: 0)
        expect(core.palette.mode == .switchApps && core.windowSwitch.scope == previousScope,
            "denied Accessibility leaves the app selection available")
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}

enum PaletteMode { case launcher, switchApps, switchWindows }
enum ClipboardFilter { case all }
enum FileSearchFilter { case all }
enum EmojiCategoryFilter { case all }
enum EmojiGridColumns { case six }
enum EmojiGridZoom { case actualSize }
struct PasteTarget: Equatable {}
struct KeyShortcut { let carbonKeyCode: Int; let modifierFlags: NSEvent.ModifierFlags }
enum HotKeyAction { case togglePalette }
struct AppEntry {
    enum Kind { case application, command }
    let kind: Kind
    let bundleID: String?
    let name: String
}
struct HotKeyBinding { let shortcut: KeyShortcut? }
@MainActor final class HotKeys {
    func binding(for action: HotKeyAction) -> HotKeyBinding? { nil }
}
@MainActor final class AppSettings { var navigationEnabled = true }
@MainActor final class AppIndex {
    enum Command { case switchWindows }
    func setCommandsVisible(_ commands: [Command], _ visible: Bool) {}
}
@MainActor final class SendToCoordinator { var isPresented = false }
@MainActor enum Permissions {
    static var allowed = true
    static func ensureAccessibility() -> Bool { allowed }
    static func openAccessibilitySettings() {}
}
@MainActor final class FixtureApp {
    var isTerminated = false
    var isHidden = true
    func unhide() { isHidden = false }
}
@MainActor enum WindowSwitchSweep {
    struct Element { let app: FixtureApp; let application: Int; let window: Int }
    struct Snapshot { var entries: [WindowSwitchEntry]; var elements: [Int: Element] }
    static var lastApplicationID: Int32?
    static func snapshot(ranks: [Int32: Int], applicationID: Int32? = nil) -> Snapshot {
        lastApplicationID = applicationID
        let entries = [
            WindowSwitchEntry(handle: 0, appName: "Editor", bundleID: "fixture", iconURL: nil,
                iconStamp: 0, title: "Draft", isMinimized: false, appRank: 0, processID: 42),
            WindowSwitchEntry(handle: 1, appName: "Editor", bundleID: "fixture", iconURL: nil,
                iconStamp: 0, title: "Archive", isMinimized: true, appRank: 0, processID: 42),
            WindowSwitchEntry(handle: 2, appName: "Editor", bundleID: "fixture", iconURL: nil,
                iconStamp: 0, title: "Hidden", isMinimized: false, appRank: 0, processID: 42, isAppHidden: true),
            WindowSwitchEntry(handle: 3, appName: "Other", bundleID: "other", iconURL: nil,
                iconStamp: 0, title: "Other", isMinimized: false, appRank: 1, processID: 43)
        ]
        return Snapshot(entries: entries, elements: Dictionary(uniqueKeysWithValues: entries.map {
            ($0.handle, Element(app: FixtureApp(), application: 42, window: $0.handle))
        }))
    }
}
@MainActor enum WindowZOrder { static func appRanks() -> [Int32: Int] { [:] } }
@MainActor enum AXWindowAccess {
    static var unminimized: [Int] = []
    static var focused: [Int] = []
    static func unminimize(_ window: Int) -> Bool { unminimized.append(window); return true }
    static func focus(_ window: Int, in application: Int, of app: FixtureApp) { focused.append(window) }
}
@MainActor final class AppRecencyMonitor {
    func entries(initialID: Int32?) -> [AppSwitchEntry] {
        [AppSwitchEntry(id: 42, name: "Editor", bundlePath: nil), AppSwitchEntry(id: 43, name: "Other", bundlePath: nil)]
    }
}
@MainActor final class PaletteCoordinator {
    unowned let core: AppCore
    var isVisible = true
    var lastRestoreFocus = true
    var targetApp: NSRunningApplication? { nil }
    init(core: AppCore) { self.core = core }
    func isShowing(_ mode: PaletteMode) -> Bool { isVisible && core.palette.mode == mode }
    func showPalette(mode: PaletteMode) { core.palette.prepare(mode: mode); core.windowSwitchCoordinator.load() }
    func syncPaletteSize() {}
    func hidePalette(restoreFocus: Bool = true) {
        lastRestoreFocus = restoreFocus
        core.appSwitchCoordinator.paletteWillHide()
        core.windowSwitch.reset()
        isVisible = false
    }
}
@MainActor final class AppCore {
    let palette = PaletteState()
    let hotKeys = HotKeys()
    let windowSwitch = WindowSwitchSession()
    let settings = AppSettings()
    let appIndex = AppIndex()
    let sendToCoordinator = SendToCoordinator()
    var isShowingDialog = false
    lazy var paletteCoordinator = PaletteCoordinator(core: self)
    lazy var appSwitchCoordinator = AppSwitchCoordinator(core: self, recency: AppRecencyMonitor())
    lazy var windowSwitchCoordinator = WindowSwitchCoordinator(settings: settings, appIndex: appIndex,
        session: windowSwitch, palette: palette, paletteCoordinator: paletteCoordinator, core: self)
    func reportFailure(title: String, message: String, symbol: String, recovery: String) async -> Bool { false }
    enum Tone { case danger }
    func showNotice(title: String, message: String, symbol: String, tone: Tone) async {}
}
