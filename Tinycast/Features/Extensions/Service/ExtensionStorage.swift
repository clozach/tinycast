import Foundation

/// One JSON file per extension: small, read whole at launch and written rarely.
@MainActor
final class ExtensionStorage {
    private struct Store: Codable {
        var localStorage: [String: StoredValue] = [:]
        var caches: [String: [String: String]] = [:]
        var preferences: [String: StoredValue] = [:]
        /// A search-bar dropdown's `storeValue` pick — host UI state, so not `LocalStorage`.
        var accessoryValues: [String: String] = [:]
        enum CodingKeys: String, CodingKey {
            case localStorage, caches, preferences, accessoryValues
        }

        init() {}

        /// Missing sections retain their defaults; unreadable documents are preserved on disk.
        init(from decoder: Decoder) throws {
            let store = try decoder.container(keyedBy: CodingKeys.self)
            localStorage =
                try store.decodeIfPresent([String: StoredValue].self, forKey: .localStorage) ?? [:]
            caches =
                try store.decodeIfPresent([String: [String: String]].self, forKey: .caches) ?? [:]
            preferences =
                try store.decodeIfPresent([String: StoredValue].self, forKey: .preferences) ?? [:]
            accessoryValues =
                try store.decodeIfPresent([String: String].self, forKey: .accessoryValues) ?? [:]
        }
    }

    /// `LocalStorage` accepts strings, numbers and booleans and must return them with their type.
    enum StoredValue: Codable, Sendable, Equatable {
        case string(String)
        case number(Double)
        case bool(Bool)

        var jsonValue: Any {
            switch self {
            case .string(let value): return value
            case .number(let value): return value
            case .bool(let value): return value
            }
        }

        init?(renderValue: RenderValue) {
            switch renderValue {
            case .string(let value): self = .string(value)
            case .number(let value): self = .number(value)
            case .bool(let value): self = .bool(value)
            default: return nil
            }
        }

        init(preference: ExtensionPreferenceValue) {
            switch preference {
            case .string(let value): self = .string(value)
            case .number(let value): self = .number(value)
            case .bool(let value): self = .bool(value)
            case .application(let path): self = .string(path)
            }
        }

        var preferenceValue: ExtensionPreferenceValue {
            switch self {
            case .string(let value): return .string(value)
            case .number(let value): return .number(value)
            case .bool(let value): return .bool(value)
            }
        }
    }

    private let directory: URL
    private let oauth: ExtensionOAuthKeychain
    private var stores: [String: Store] = [:]
    /// Preserve unexpected plaintext credentials or unreadable documents until explicitly repaired.
    private var protectedFiles: [String: StorageError] = [:]
    /// Writes are coalesced, so a busy `Cache` doesn't hit the disk per key.
    private var dirty: Set<String> = []
    private var flushTask: Task<Void, Never>?

    init(directory: URL, oauth: ExtensionOAuthKeychain = ExtensionOAuthKeychain()) {
        self.directory = directory
        self.oauth = oauth
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - LocalStorage

    func localStorageValue(extension name: String, key: String) -> StoredValue? {
        store(for: name).localStorage[key]
    }

    func allLocalStorage(extension name: String) -> [String: StoredValue] {
        store(for: name).localStorage
    }

    func setLocalStorage(extension name: String, key: String, value: StoredValue) {
        mutate(name) { $0.localStorage[key] = value }
    }

    func removeLocalStorage(extension name: String, key: String) {
        mutate(name) { $0.localStorage.removeValue(forKey: key) }
    }

    func clearLocalStorage(extension name: String) {
        mutate(name) { $0.localStorage.removeAll() }
    }

    // MARK: - Search-bar dropdowns

    func accessoryValue(extension name: String, key: String) -> String? {
        store(for: name).accessoryValues[key]
    }

    func setAccessoryValue(extension name: String, key: String, value: String) {
        mutate(name) { $0.accessoryValues[key] = value }
    }

    // MARK: - Cache

    func caches(extension name: String) -> [String: [String: String]] {
        store(for: name).caches
    }

    /// `nil` removes the key; a `nil` key clears the namespace.
    func setCache(extension name: String, namespace: String, key: String?, value: String?) {
        mutate(name) { store in
            guard let key else {
                store.caches[namespace] = [:]
                return
            }
            var bucket = store.caches[namespace] ?? [:]
            if let value { bucket[key] = value } else { bucket.removeValue(forKey: key) }
            store.caches[namespace] = bucket
        }
    }

    func clearCache(extension name: String, namespace: String) {
        mutate(name) { $0.caches[namespace] = [:] }
    }

    // MARK: - OAuth tokens

    func oauthTokens(extension name: String, provider: String) throws -> String? {
        try requireProtectedOAuthStorage(for: name)
        return try oauth.getTokens(extensionName: name, providerId: provider)
    }

    /// `nil` signs the provider out.
    func setOAuthTokens(extension name: String, provider: String, tokens: String?) throws {
        try requireProtectedOAuthStorage(for: name)
        if let tokens {
            try oauth.setTokens(tokens, extensionName: name, providerId: provider)
        } else {
            try oauth.removeTokens(extensionName: name, providerId: provider)
        }
    }

    // MARK: - Preferences

    func preference(extension name: String, key: String) -> ExtensionPreferenceValue? {
        store(for: name).preferences[key]?.preferenceValue
    }

    func setPreference(extension name: String, key: String, value: ExtensionPreferenceValue?) {
        mutate(name) { store in
            if let value {
                store.preferences[key] = StoredValue(preference: value)
            } else {
                store.preferences.removeValue(forKey: key)
            }
        }
    }

    /// Manifest defaults overlaid with the user's — what `getPreferenceValues()` sees.
    func resolvedPreferences(
        extension name: String, schemas: [ExtensionPreferenceSchema]
    ) -> [String: ExtensionPreferenceValue] {
        var resolved: [String: ExtensionPreferenceValue] = [:]
        for schema in schemas {
            resolved[schema.name] = schema.runtimeValue(preference(extension: name, key: schema.name))
        }
        return resolved
    }

    /// A command with an unset required preference must not run.
    func missingRequiredPreferences(
        extension name: String, schemas: [ExtensionPreferenceSchema]
    ) -> [ExtensionPreferenceSchema] {
        schemas.filter { schema in
            guard schema.required else { return false }
            let value = preference(extension: name, key: schema.name) ?? schema.effectiveDefault
            if case .string(let text) = value { return text.isEmpty }
            return false
        }
    }

    func removeAll(extension name: String) throws {
        try oauth.removeAllTokens(extensionName: name)
        let file = fileURL(for: name)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        stores.removeValue(forKey: name)
        protectedFiles.removeValue(forKey: name)
        dirty.remove(name)
    }

    // MARK: - Persistence

    private func store(for name: String) -> Store {
        if let existing = stores[name] { return existing }
        let file = fileURL(for: name)
        var loaded = Store()
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let data = try Data(contentsOf: file)
                let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let tokens = document?["oauthTokens"], !(tokens is NSNull) {
                    if (tokens as? [String: Any])?.isEmpty != true {
                        protectedFiles[name] = .plaintextOAuth(file)
                    }
                }
                loaded = try JSONDecoder().decode(Store.self, from: data)
            } catch {
                protectedFiles[name] = protectedFiles[name] ?? .unreadable(file)
            }
        }
        stores[name] = loaded
        return loaded
    }

    private func requireProtectedOAuthStorage(for name: String) throws {
        _ = store(for: name)
        if let error = protectedFiles[name] { throw error }
    }

    private func mutate(_ name: String, _ body: (inout Store) -> Void) {
        var current = store(for: name)
        guard protectedFiles[name] == nil else { return }
        body(&current)
        stores[name] = current
        dirty.insert(name)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.flush()
        }
    }

    func flush() {
        flushTask?.cancel()
        flushTask = nil
        let pending = dirty
        dirty.removeAll()
        for name in pending {
            guard protectedFiles[name] == nil, let store = stores[name],
                let data = try? JSONEncoder().encode(store)
            else { continue }
            try? data.write(to: fileURL(for: name), options: .atomic)
        }
    }

    private func fileURL(for name: String) -> URL {
        directory.appendingPathComponent("\(ExtensionCatalog.safeName(name)).json")
    }

    enum StorageError: LocalizedError {
        case plaintextOAuth(URL)
        case unreadable(URL)

        var errorDescription: String? {
            switch self {
            case .plaintextOAuth(let file):
                return "Older OAuth credentials were found in \(file.path). Tinycast left this file "
                    + "unchanged. Migrate its oauthTokens section to Keychain, or remove that section "
                    + "then restart Tinycast and reconnect, before using this extension."
            case .unreadable(let file):
                return "Tinycast could not read \(file.path) and left it unchanged. "
                    + "Restore or repair that file, then restart Tinycast before using this extension."
            }
        }
    }
}
