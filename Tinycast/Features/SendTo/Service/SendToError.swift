import Foundation

enum SendToError: LocalizedError {
    case emptyPayload
    case unavailableFile(String)
    case unreadableImage(String)
    case clipboardWrite
    case accessibility
    case appUnavailable(String)
    case activationTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .emptyPayload: return "There is nothing to send."
        case .unavailableFile(let name): return "“\(name)” is no longer available."
        case .unreadableImage(let name): return "“\(name)” could not be read as an image."
        case .clipboardWrite: return "The item could not be placed on the clipboard."
        case .accessibility: return "Allow Tinycast in System Settings → Privacy & Security → Accessibility to paste into an app."
        case .appUnavailable(let name): return "“\(name)” is no longer running."
        case .activationTimedOut(let name):
            return "“\(name)” did not become ready to receive the paste. The item is on the clipboard."
        }
    }
}
