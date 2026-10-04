import AppKit
import SwiftUI

@main
@MainActor
struct SendToFocusTests {
    private static var checks = 0
    private static var failures = 0

    static func main() async throws {
        _ = NSApplication.shared
        let controller = SendToController()
        let parent = FocusWindow()
        var cancellations: [Bool] = []
        func show() -> SendToPanel {
            controller.show(
                session: SendToSession(), parent: parent, metrics: InterfaceMetrics(),
                cancel: { cancellations.append($0) }, send: { _ in })
            return SendToPanel.latest!
        }
        func resign(_ panel: SendToPanel) {
            controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
        }
        let first = show()
        parent.key = false
        resign(first)
        check(cancellations.isEmpty, "resignation waits for AppKit's next key window")
        parent.key = true
        try await Task.sleep(for: .milliseconds(10))
        check(cancellations == [true], "returning to parent preserves the source window")
        cancellations = []
        parent.key = false
        resign(first)
        try await Task.sleep(for: .milliseconds(10))
        check(cancellations == [false], "external focus dismisses the source palette")
        cancellations = []
        resign(first)
        controller.close(restoreFocus: false)
        try await Task.sleep(for: .milliseconds(10))
        check(cancellations.isEmpty, "closing cancels a pending focus decision")
        let second = show()
        resign(first)
        try await Task.sleep(for: .milliseconds(10))
        check(cancellations.isEmpty, "an old chooser's notification cannot cancel the current one")
        resign(second)
        controller.close(restoreFocus: false)
        let third = show()
        try await Task.sleep(for: .milliseconds(10))
        check(cancellations.isEmpty, "reopening cannot inherit the old deferred cancellation")
        resign(third)
        third.key = true
        try await Task.sleep(for: .milliseconds(10))
        check(cancellations.isEmpty, "a chooser that regains key remains open")
        controller.close(restoreFocus: false)
        print("\(checks - failures)/\(checks) Send to focus checks passed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        if !condition() {
            failures += 1
            print("FAIL: \(label)")
        }
    }
}

@MainActor
final class FocusWindow: NSWindow {
    var key = false
    override var isKeyWindow: Bool { key }
}

@MainActor
final class SendToPanel: NSPanel {
    static weak var latest: SendToPanel?
    var onKeyDown: ((NSEvent) -> Bool)?
    var key = false
    override var isKeyWindow: Bool { key }

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        Self.latest = self
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {}
    override func orderFrontRegardless() {}
}

@MainActor
final class SendToSession {
    var query = ""
    var selected: SendToTarget?
    func move(_ delta: Int) {}
}

struct SendToTarget {}

struct InterfaceMetrics: Sendable {
    struct Size: Sendable {
        let dialogWidth: CGFloat = 100
        let panelHeight: CGFloat = 100
    }
    let size = Size()
}

private struct MetricsKey: EnvironmentKey {
    static let defaultValue = InterfaceMetrics()
}

extension EnvironmentValues {
    var metrics: InterfaceMetrics {
        get { self[MetricsKey.self] }
        set { self[MetricsKey.self] = newValue }
    }
}

struct SendToView: View {
    let session: SendToSession
    let cancel: () -> Void
    let send: (SendToTarget) -> Void
    var body: some View { Color.clear }
}
