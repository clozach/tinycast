import AppKit

@MainActor @Observable
final class SendToCoordinator {
    private unowned let core: AppCore
    @ObservationIgnored private let controller = SendToController()
    @ObservationIgnored private let sources = NSMapTable<NSWindow, SendToSource.SourceView>.weakToWeakObjects()
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var delivery: Task<Void, Never>?
    private(set) var isPresented = false

    init(core: AppCore) { self.core = core }

    isolated deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        delivery?.cancel()
    }

    func start() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @MainActor [weak self] event in
            guard let self, core.hotKeys.recordingAction == nil,
                event.modifierFlags.intersection([.command, .option, .control, .shift]) == [.command, .shift],
                (ASCIIKeyboardLayout.character(for: event) ?? event.charactersIgnoringModifiers)?.lowercased() == "s"
            else { return event }
            if !event.isARepeat { request() }
            return nil
        }
    }

    func register(_ source: SendToSource.SourceView, in window: NSWindow) {
        sources.setObject(source, forKey: window)
    }

    func request() {
        guard !isPresented, !core.isShowingDialog else { return }
        isPresented = true
        let key = NSApp.keyWindow
        let parent = key?.parent ?? key
        let source = parent.flatMap { sources.object(forKey: $0) }
        let selected = Self.selectedText(in: parent, includingFieldEditor: source?.prefersSelectedText ?? true)
        let payload = selected.map(SendToPayload.text) ?? source?.payload?()
        present(payload, source: selected == nil ? source?.label ?? "Selected item" : "Selected text", parent: parent)
    }

    private func present(_ payload: SendToPayload?, source: String, parent: NSWindow?) {
        do {
            guard let resolved = try payload ?? SendToService.snapshot() else {
                isPresented = false
                core.showMessage("Select an item or copy something to send")
                return
            }
            let session = SendToSession(
                payload: resolved, source: payload == nil ? "Clipboard" : source,
                targets: try SendToService.targets(for: resolved))
            controller.show(
                session: session, parent: parent, metrics: core.settings.interfaceSize.metrics,
                cancel: { [weak self, weak parent] restoreFocus in
                    self?.cancel(restoreFocus: restoreFocus, from: parent)
                },
                send: { [weak self] target in self?.send(session.payload, to: target) })
        } catch {
            isPresented = false
            core.showMessage(error.localizedDescription, tone: .danger)
        }
    }

    private func cancel(restoreFocus: Bool, from parent: NSWindow?) {
        controller.close(restoreFocus: restoreFocus)
        isPresented = false
        if !restoreFocus, parent is PalettePanel {
            core.paletteCoordinator.hidePalette(restoreFocus: false)
        }
    }

    private func send(_ payload: SendToPayload, to target: SendToTarget) {
        controller.close(restoreFocus: false)
        isPresented = false
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        delivery?.cancel()
        delivery = Task { [weak self] in
            do {
                try await SendToService.send(payload, to: target)
            } catch is CancellationError {
                return
            } catch {
                self?.core.showMessage(error.localizedDescription, tone: .danger)
            }
        }
    }

    private static func selectedText(in window: NSWindow?, includingFieldEditor: Bool) -> String? {
        guard let editor = window?.firstResponder as? NSTextView,
            includingFieldEditor || !editor.isFieldEditor,
            !(editor.delegate is NSSecureTextField)
        else { return nil }
        let text = editor.string as NSString
        let range = editor.selectedRange()
        guard range.length > 0, range.location <= text.length,
            range.length <= text.length - range.location
        else { return nil }
        return text.substring(with: range)
    }
}
