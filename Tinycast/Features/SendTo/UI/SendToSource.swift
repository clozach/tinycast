import AppKit
import SwiftUI

/// Each window supplies its current content when asked, without keeping an old selection alive.
struct SendToSource: NSViewRepresentable {
    let coordinator: SendToCoordinator
    var prefersSelectedText = true
    var label = "Selected item"
    let payload: () -> SendToPayload?

    func makeNSView(context: Context) -> SourceView {
        SourceView(coordinator: coordinator)
    }

    func updateNSView(_ view: SourceView, context: Context) {
        view.prefersSelectedText = prefersSelectedText
        view.label = label
        view.payload = payload
    }

    final class SourceView: NSView {
        private weak var coordinator: SendToCoordinator?
        var prefersSelectedText = true
        var label = "Selected item"
        var payload: (() -> SendToPayload?)?

        init(coordinator: SendToCoordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { coordinator?.register(self, in: window) }
        }
    }
}
