import AppKit
import Carbon.HIToolbox

/// Only UniMagic's shared invocation chord needs coordination across the two applications.
@MainActor
enum GlyphPickerShortcut {
    static let entryID = "extension:unimagic/unimagic"
    static let shortcut = KeyShortcut(keyCode: kVK_Space, modifierFlags: [.control, .command])!
    private static let appID = "com.clozach.unimagic.mac"

    enum OwnershipChange { case release, recheck }

    static func notifyController(_ change: OwnershipChange) {
        guard let ownID = Bundle.main.bundleIdentifier, ["com.tinycast.app", "com.tinycast.app.clozach"].contains(ownID)
        else { return }
        switch change {
        case .release: _ = send("release", id: 2, to: appID, port: "shortcut")
        case .recheck: _ = send("recheck", id: 3, to: appID, port: "shortcut")
        }
    }

    static func forwardToFocusedStandalonePicker() -> Bool {
        send("invoke", id: 1, to: "\(appID).picker", port: "invoke")
    }

    private static func send(_ message: String, id: Int32, to bundleID: String, port suffix: String) -> Bool {
        guard Bundle.main.bundleIdentifier != bundleID,
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
            let port = CFMessagePortCreateRemote(nil, "\(bundleID).\(suffix)" as CFString)
        else { return false }
        var reply: Unmanaged<CFData>?
        let result = CFMessagePortSendRequest(port, id, Data(message.utf8) as CFData, 0.15, 0.25,
            CFRunLoopMode.defaultMode.rawValue, &reply)
        let data = reply?.takeRetainedValue() as Data?
        return result == kCFMessagePortSuccess && data == Data("1".utf8)
    }
}
