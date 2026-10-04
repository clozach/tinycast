import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class SendToController: NSObject, NSWindowDelegate {
    private var panel: SendToPanel?
    private weak var parentWindow: NSWindow?
    private var onCancel: ((Bool) -> Void)?
    private var focusCheck: Task<Void, Never>?

    isolated deinit { focusCheck?.cancel() }

    func show(
        session: SendToSession, parent: NSWindow?, metrics: InterfaceMetrics,
        cancel: @escaping (Bool) -> Void, send: @escaping (SendToTarget) -> Void
    ) {
        let panel = SendToPanel()
        let hosting = NSHostingView(
            rootView: SendToView(session: session, cancel: { cancel(true) }, send: send)
                .environment(\.metrics, metrics))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setContentSize(CGSize(width: metrics.size.dialogWidth, height: metrics.size.panelHeight))
        panel.delegate = self
        panel.onKeyDown = { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard modifiers.isEmpty else { return false }
            switch Int(event.keyCode) {
            case kVK_Escape: cancel(true)
            case kVK_LeftArrow where session.query.isEmpty: cancel(true)
            case kVK_UpArrow: session.move(-1)
            case kVK_DownArrow: session.move(1)
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if let target = session.selected { send(target) }
            default: return false
            }
            return true
        }
        self.panel = panel
        parentWindow = parent
        onCancel = cancel
        if let parent { parent.addChildWindow(panel, ordered: .above) }
        let visible = (parent?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let anchor = parent?.frame ?? visible
        let x = min(max(anchor.midX - panel.frame.width / 2, visible.minX), visible.maxX - panel.frame.width)
        let y = min(max(anchor.midY - panel.frame.height / 2, visible.minY), visible.maxY - panel.frame.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        if let field = Self.searchField(in: hosting) { panel.makeFirstResponder(field) }
    }

    func close(restoreFocus: Bool) {
        focusCheck?.cancel()
        focusCheck = nil
        guard let panel else { return }
        self.panel = nil
        onCancel = nil
        panel.delegate = nil
        panel.onKeyDown = nil
        parentWindow?.removeChildWindow(panel)
        panel.orderOut(nil)
        if restoreFocus, let parentWindow, parentWindow.isVisible { parentWindow.makeKey() }
        parentWindow = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        focusCheck?.cancel()
        focusCheck = Task { @MainActor [weak self, weak panel] in
            // AppKit resigns the old key window before making the next one key.
            await Task.yield()
            guard !Task.isCancelled, let self, let panel,
                self.panel === panel, !panel.isKeyWindow
            else { return }
            focusCheck = nil
            onCancel?(parentWindow?.isKeyWindow == true)
        }
    }

    private static func searchField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { searchField(in: $0) }.first
    }
}
