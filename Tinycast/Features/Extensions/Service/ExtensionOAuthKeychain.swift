import Foundation
import Security

/// Injected in tests so verification never reads or writes the user's Keychain.
@MainActor
protocol ExtensionOAuthTokenStore {
    func get(account: String) throws -> String?
    func set(_ value: String, account: String) throws
    func remove(account: String) throws
    func accounts() throws -> [String]
}

struct ExtensionOAuthKeychainError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        "Could not \(operation) extension sign-in credentials in Keychain (status \(status)). "
            + "Unlock your Keychain or allow Tinycast access, then try again."
    }
}

@MainActor
struct KeychainOAuthTokenStore: ExtensionOAuthTokenStore {
    // Preserve this fork's pre-upgrade service and account identities.
    static let serviceName = "com.tinycast.extensions.oauth"

    private func query(account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
        ]
        if let account { query[kSecAttrAccount as String] = account }
        return query
    }

    func get(account: String) throws -> String? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw ExtensionOAuthKeychainError(operation: "read", status: status)
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw ExtensionOAuthKeychainError(operation: "decode", status: errSecDecode)
        }
        return value
    }

    func set(_ value: String, account: String) throws {
        let query = query(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw ExtensionOAuthKeychainError(operation: "save", status: status)
        }
    }

    func remove(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ExtensionOAuthKeychainError(operation: "remove", status: status)
        }
    }

    func accounts() throws -> [String] {
        var query = query()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else {
            throw ExtensionOAuthKeychainError(operation: "list", status: status)
        }
        guard let items = item as? [[String: Any]] else {
            throw ExtensionOAuthKeychainError(operation: "decode", status: errSecDecode)
        }
        return try items.map { attributes in
            guard let account = attributes[kSecAttrAccount as String] as? String else {
                throw ExtensionOAuthKeychainError(operation: "decode", status: errSecDecode)
            }
            return account
        }
    }
}

/// OAuth JSON is opaque here and never enters ExtensionStorage's on-disk document.
@MainActor
struct ExtensionOAuthKeychain {
    private let store: any ExtensionOAuthTokenStore

    init(store: any ExtensionOAuthTokenStore = KeychainOAuthTokenStore()) {
        self.store = store
    }

    static func accountKey(extensionName: String, providerId: String?) -> String {
        guard let providerId, !providerId.isEmpty else { return extensionName }
        return "\(extensionName):\(providerId)"
    }

    func getTokens(extensionName: String, providerId: String?) throws -> String? {
        try store.get(account: Self.accountKey(extensionName: extensionName, providerId: providerId))
    }

    func setTokens(_ value: String, extensionName: String, providerId: String?) throws {
        try store.set(value, account: Self.accountKey(extensionName: extensionName, providerId: providerId))
    }

    func removeTokens(extensionName: String, providerId: String?) throws {
        try store.remove(account: Self.accountKey(extensionName: extensionName, providerId: providerId))
    }

    func removeAllTokens(extensionName: String) throws {
        for account in try store.accounts()
        where account == extensionName || account.hasPrefix("\(extensionName):") {
            try store.remove(account: account)
        }
    }
}
