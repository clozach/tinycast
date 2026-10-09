import AppKit
import Carbon.HIToolbox

@MainActor
@Observable
final class AppSwitchCoordinator {
    private unowned let core: AppCore
    private let recency: AppRecencyMonitor
    private(set) var entries: [AppSwitchEntry] = []
    private(set) var gesture = AppSwitchGesture()
    @ObservationIgnored private var pendingShortcut: KeyShortcut?
    @ObservationIgnored private var presentedQuery = ""
    @ObservationIgnored private var appListQuery = ""
    @ObservationIgnored private var restoredFrame: PaletteFrame?
    @ObservationIgnored private var wasEditingField = false
    @ObservationIgnored private var wasControlListOpen = false
    @ObservationIgnored private var releaseTask: Task<Void, Never>?
    private static let modifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]

    init(core: AppCore, recency: AppRecencyMonitor) {
        self.core = core
        self.recency = recency
    }

    var filtered: [AppSwitchEntry] { AppSwitchOrder.filtered(entries, query: core.palette.query) }
    var releasesToActivate: Bool { gesture.isSwitching }
    var restoresHiddenPalette: Bool {
        !core.palette.isVisible && restoredFrame?.mode == core.palette.mode
            && restoredFrame?.query == core.palette.query
    }

    func beforeHotKey(_ action: HotKeyAction) -> Bool {
        pendingShortcut = nil
        let shortcut = core.hotKeys.binding(for: action)?.shortcut
        if !core.paletteCoordinator.isVisible {
            cancelGesture()
            restoredFrame = nil
            pendingShortcut = shortcut
            return false
        }
        guard let shortcut, let trigger = gesture.trigger,
            trigger.matches(keyCode: shortcut.carbonKeyCode, modifiers: Self.heldModifiers)
        else {
            cancelGesture()
            return false
        }
        return press(keyCode: shortcut.carbonKeyCode, modifiers: Self.heldModifiers)
    }

    func afterHotKey(_ action: HotKeyAction) {
        defer { pendingShortcut = nil }
        guard let shortcut = pendingShortcut, core.paletteCoordinator.isVisible else { return }
        presentedQuery = core.palette.query
        gesture.begin(.init(
            keyCode: shortcut.carbonKeyCode,
            modifiers: UInt64(shortcut.modifierFlags.intersection(Self.modifiers).rawValue),
            shift: UInt64(NSEvent.ModifierFlags.shift.rawValue)))
        watchRelease()
    }

    func hotKeyReleased(_ action: HotKeyAction) {
        guard core.hotKeys.binding(for: action)?.shortcut?.carbonKeyCode == gesture.trigger?.keyCode else { return }
        sampleRelease()
    }

    func handle(_ event: NSEvent) -> Bool {
        guard core.paletteCoordinator.isVisible else { return false }
        if event.type == .keyDown {
            if Int(event.keyCode) == kVK_Escape, escapeWhileSwitching() { return true }
            let canDrill = !event.modifierFlags.contains(.command) || releasesToActivate || core.palette.query.isEmpty
            if Int(event.keyCode) == kVK_RightArrow, core.palette.mode == .switchApps,
                !core.palette.menuOpen, !core.palette.isComposing,
                event.modifierFlags.isDisjoint(with: [.shift, .control]),
                canDrill {
                showWindows(at: core.palette.selection, includingHidden: event.modifierFlags.contains(.option))
                return true
            }
            let flags = UInt64(event.modifierFlags.intersection(Self.modifiers).rawValue)
            if let trigger = gesture.trigger, trigger.matches(keyCode: Int(event.keyCode), modifiers: flags) {
                return press(keyCode: Int(event.keyCode), modifiers: flags, isRepeat: event.isARepeat)
            }
            cancelGesture()
        } else if [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].contains(event.type) {
            cancelGesture()
        } else if event.type == .keyUp || event.type == .flagsChanged {
            sampleRelease()
        }
        return false
    }

    func activity() { cancelGesture() }

    func escapeWhileSwitching() -> Bool {
        guard core.palette.mode == .switchApps, releasesToActivate else { return false }
        core.paletteCoordinator.hidePalette()
        return true
    }

    func queryChanged() -> Bool {
        if core.palette.mode == .switchApps {
            guard core.palette.query != appListQuery else { return false }
            appListQuery = core.palette.query
        }
        guard core.palette.query != presentedQuery else { return false }
        presentedQuery = core.palette.query
        cancelGesture()
        return true
    }

    func paletteWillHide() {
        cancelGesture()
        if core.palette.mode == .switchWindows,
            core.windowSwitch.scope.applicationID != nil,
            core.palette.backStack.last?.mode == .switchApps {
            _ = core.palette.pop(preservingScreenState: true)
        }
        if core.palette.mode == .switchApps {
            _ = core.palette.pop(preservingScreenState: true)
            restoredFrame = PaletteFrame(
                mode: core.palette.mode, query: core.palette.query, selection: core.palette.selection)
            core.palette.noteEditingField(wasEditingField)
            core.palette.noteControlListOpen(wasControlListOpen)
        } else {
            restoredFrame = nil
        }
        entries = []
    }

    func activate(at selection: Int) {
        let rows = filtered
        guard rows.indices.contains(selection) else { return }
        let app = NSRunningApplication(processIdentifier: rows[selection].id)
        core.paletteCoordinator.hidePalette(restoreFocus: app == nil || app?.isTerminated == true)
        if app?.isTerminated == false { app?.activate() }
    }

    func showWindows(at selection: Int, includingHidden: Bool = false) {
        let rows = filtered
        guard rows.indices.contains(selection) else { return }
        cancelGesture()
        core.windowSwitchCoordinator.showWindows(of: rows[selection], includingHidden: includingHidden)
    }

    func present() {
        entries = recency.entries(initialID: core.paletteCoordinator.targetApp?.processIdentifier)
        wasEditingField = core.palette.isEditingField
        wasControlListOpen = core.palette.isControlListOpen
        core.palette.pushCarryingQuery(mode: .switchApps)
        core.palette.query = ""
        core.palette.selection = 0
        core.palette.noteEditingField(false)
        core.palette.noteControlListOpen(false)
        core.palette.focusToken = UUID()
        core.palette.followToken = UUID()
        presentedQuery = core.palette.query
        appListQuery = core.palette.query
        core.paletteCoordinator.syncPaletteSize()
    }

    private func press(keyCode: Int, modifiers: UInt64, isRepeat: Bool = false) -> Bool {
        switch gesture.press(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat) {
        case .ignored: return false
        case .repeatPress: return true
        case .enter:
            present()
        case .step(let backwards):
            if let next = AppSwitchOrder.next(from: core.palette.selection, count: filtered.count, backwards: backwards) {
                core.palette.selection = next
                core.palette.followToken = UUID()
            }
        }
        return true
    }

    private static var heldModifiers: UInt64 {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue))
        return UInt64(flags.intersection(modifiers).rawValue)
    }

    private func sampleRelease() {
        guard !core.isShowingDialog, !core.sendToCoordinator.isPresented, !core.palette.menuOpen else {
            cancelGesture()
            return
        }
        guard let trigger = gesture.trigger else { return }
        let keyDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(trigger.keyCode))
        if gesture.sample(modifiers: Self.heldModifiers, keyIsDown: keyDown) {
            activate(at: core.palette.selection)
        }
        if gesture.trigger == nil { releaseTask?.cancel(); releaseTask = nil }
    }

    private func watchRelease() {
        releaseTask?.cancel()
        guard gesture.trigger != nil else { return }
        releaseTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled, let self else { return }
                self.sampleRelease()
            }
        }
    }

    private func cancelGesture() {
        gesture.cancel()
        releaseTask?.cancel()
        releaseTask = nil
    }

    isolated deinit { releaseTask?.cancel() }
}
