import Foundation

/// What TCC allows for Contacts, in the same three states as `CalendarAccess`.
enum ContactsAccess: Sendable {
    case notDetermined
    case granted
    /// Denied, restricted or limited to none: only System Settings changes it.
    case denied
}
