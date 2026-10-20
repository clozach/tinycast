import AppKit
import SwiftUI

struct TeachSource: NSViewRepresentable {
    let coordinator: TeachCoordinator
    let entry: () -> AppEntry?

    func makeNSView(context: Context) -> SourceView { SourceView(coordinator: coordinator) }
    func updateNSView(_ view: SourceView, context: Context) { view.entry = entry }

    final class SourceView: NSView {
        private weak var coordinator: TeachCoordinator?
        var entry: (() -> AppEntry?)?

        init(coordinator: TeachCoordinator) {
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
