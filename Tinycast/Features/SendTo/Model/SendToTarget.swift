import Foundation

enum SendToTarget: Equatable, Identifiable, Sendable {
    case open(app: URL, items: [URL])
    case paste(pid: Int32, name: String, app: URL?)

    var id: String {
        switch self {
        case .open(let app, _): return "open:\(app.standardizedFileURL.path)"
        case .paste(let pid, _, _): return "paste:\(pid)"
        }
    }

    var name: String {
        switch self {
        case .open(let app, _): return app.deletingPathExtension().lastPathComponent
        case .paste(_, let name, _): return name
        }
    }

    var appURL: URL? {
        switch self {
        case .open(let app, _): return app
        case .paste(_, _, let app): return app
        }
    }

    var isOpen: Bool {
        if case .open = self { return true }
        return false
    }
}
