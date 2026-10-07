import Foundation

struct AppSwitchEntry: Identifiable, Equatable, Sendable {
    let id: Int32
    let name: String
    let bundlePath: String?
}
