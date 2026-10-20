import Foundation

/// All extension harnesses inject this store; none may use the user's real Keychain.
@MainActor
final class ExtensionTestTokenStore: ExtensionOAuthTokenStore {
    private var values: [String: String] = [:]

    func get(account: String) throws -> String? { values[account] }
    func set(_ value: String, account: String) throws { values[account] = value }
    func remove(account: String) throws { values.removeValue(forKey: account) }
    func accounts() throws -> [String] { Array(values.keys) }
}
