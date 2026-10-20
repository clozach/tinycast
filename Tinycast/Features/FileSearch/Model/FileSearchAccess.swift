import Foundation

enum FileSearchAccess: Sendable {
    case full
    case limited

    init(fullDiskAccess: Bool) {
        self = fullDiskAccess ? .full : .limited
    }

    var indexFileName: String {
        switch self {
        case .full: "index.bin"
        case .limited: "readable-index.bin"
        }
    }
}
