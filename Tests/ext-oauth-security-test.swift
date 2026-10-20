import Foundation
import Security

// Model stand-ins only; the storage and Keychain routing under test are production sources.
enum RenderValue { case string(String), number(Double), bool(Bool), null }
enum ExtensionPreferenceValue { case string(String), number(Double), bool(Bool), application(String) }
struct ExtensionPreferenceSchema {
    let name: String
    let required: Bool
    let effectiveDefault: ExtensionPreferenceValue
    func runtimeValue(_ value: ExtensionPreferenceValue?) -> ExtensionPreferenceValue {
        value ?? effectiveDefault
    }
}
enum ExtensionCatalog {
    static func safeName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "@", with: "")
    }
}

@MainActor
private final class MockTokens: ExtensionOAuthTokenStore {
    var values: [String: String] = [:]
    var failure: String?
    var calls = 0
    private func check(_ operation: String) throws {
        calls += 1
        if failure == operation {
            throw ExtensionOAuthKeychainError(operation: operation, status: errSecInteractionNotAllowed)
        }
    }
    func get(account: String) throws -> String? { try check("read"); return values[account] }
    func set(_ value: String, account: String) throws { try check("save"); values[account] = value }
    func remove(account: String) throws { try check("remove"); values.removeValue(forKey: account) }
    func accounts() throws -> [String] { try check("list"); return values.keys.sorted() }
}

@main
@MainActor
struct ExtensionOAuthSecurityTests {
    static var failures = 0
    static var passes = 0
    static let dummy = #"{"accessToken":"DUMMY_ACCESS_NOT_VALID","refreshToken":"DUMMY_REFRESH_NOT_VALID"}"#

    static func expect(_ condition: Bool, _ message: String) {
        if condition { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static func expectError(_ message: String, _ operation: () throws -> Void) {
        do { try operation(); expect(false, message) } catch { expect(true, message) }
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-oauth-security-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try routingAndPersistence(directory)
        try keychainFailures(directory)
        try legacyPreservation(directory)
        try uninstall(directory)
        print("\(passes) passed, \(failures) failed (synthetic tokens; no real Keychain access)")
        exit(failures == 0 ? 0 : 1)
    }

    private static func routingAndPersistence(_ directory: URL) throws {
        let tokens = MockTokens()
        tokens.values["old-extension"] = dummy
        tokens.values["old-extension:named"] = dummy
        let oauth = ExtensionOAuthKeychain(store: tokens)
        let storage = ExtensionStorage(directory: directory, oauth: oauth)
        expect(KeychainOAuthTokenStore.serviceName == "com.tinycast.extensions.oauth", "legacy service")
        expect(try oauth.getTokens(extensionName: "old-extension", providerId: nil) == dummy, "nil identity")
        expect(try storage.oauthTokens(extension: "old-extension", provider: "") == dummy, "empty identity")
        expect(try storage.oauthTokens(extension: "old-extension", provider: "named") == dummy, "provider identity")
        expect(try storage.oauthTokens(extension: "other-extension", provider: "") == nil, "extension isolation")
        expect(try storage.oauthTokens(extension: "old-extension", provider: "other") == nil, "provider isolation")
        try storage.setOAuthTokens(extension: "fresh", provider: "", tokens: dummy)
        storage.flush()
        expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("fresh.json").path),
               "OAuth-only save creates no JSON file")
        storage.setLocalStorage(extension: "fresh", key: "ordinary", value: .string("kept"))
        storage.setPreference(extension: "fresh", key: "theme", value: .string("dark"))
        storage.flush()
        let data = try Data(contentsOf: directory.appendingPathComponent("fresh.json"))
        let raw = String(decoding: data, as: UTF8.self)
        expect(!raw.contains("DUMMY_") && !raw.contains("oauthTokens"), "ordinary JSON excludes credentials")
        let reloaded = ExtensionStorage(directory: directory, oauth: oauth)
        expect(reloaded.localStorageValue(extension: "fresh", key: "ordinary") == .string("kept"), "ordinary reload")
        expect(try reloaded.oauthTokens(extension: "fresh", provider: "") == dummy, "secure reload")
        try reloaded.setOAuthTokens(extension: "fresh", provider: "", tokens: nil)
        expect(tokens.values["fresh"] == nil, "sign-out removes Keychain account")
    }

    private static func keychainFailures(_ directory: URL) throws {
        let tokens = MockTokens()
        tokens.values["failed"] = dummy
        let storage = ExtensionStorage(directory: directory, oauth: ExtensionOAuthKeychain(store: tokens))
        tokens.failure = "read"
        expectError("read denial is not a silent logout") { _ = try storage.oauthTokens(extension: "failed", provider: "") }
        tokens.failure = "save"
        expectError("save denial propagates") { try storage.setOAuthTokens(extension: "failed", provider: "", tokens: "REPLACEMENT") }
        expect(tokens.values["failed"] == dummy, "failed save retains previous credentials")
        tokens.failure = "remove"
        expectError("sign-out denial propagates") { try storage.setOAuthTokens(extension: "failed", provider: "", tokens: nil) }
        expect(tokens.values["failed"] == dummy, "failed sign-out retains previous credentials")
        storage.flush()
        expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("failed.json").path),
               "Keychain failure never falls back to plaintext")
    }

    private static func legacyPreservation(_ directory: URL) throws {
        let tokens = MockTokens()
        let legacyCases = [
            #"{"oauthTokens":{"provider":"DUMMY_LEGACY"},"localStorage":{},"preferences":{}}"#,
            #"{"oauthTokens":"unexpected-value"}"#,
            #"{"oauthTokens":{"provider":"DUMMY_LEGACY"},"localStorage":BROKEN"#,
        ]
        for (index, text) in legacyCases.enumerated() {
            let name = "legacy-\(index)"
            let file = directory.appendingPathComponent("\(name).json")
            let original = Data(text.utf8)
            try original.write(to: file)
            let storage = ExtensionStorage(directory: directory, oauth: ExtensionOAuthKeychain(store: tokens))
            let priorCalls = tokens.calls
            expectError("legacy read blocked") { _ = try storage.oauthTokens(extension: name, provider: "provider") }
            expectError("legacy save blocked") { try storage.setOAuthTokens(extension: name, provider: "provider", tokens: dummy) }
            expectError("legacy sign-out blocked") { try storage.setOAuthTokens(extension: name, provider: "provider", tokens: nil) }
            storage.setLocalStorage(extension: name, key: "new", value: .string("must-not-rewrite"))
            storage.flush()
            expect(try Data(contentsOf: file) == original, "unexpected legacy document remains byte-for-byte unchanged")
            expect(tokens.calls == priorCalls, "legacy detection fails before any Keychain mutation")
        }
        let file = directory.appendingPathComponent("legacy-empty.json")
        try Data(#"{"oauthTokens":{},"localStorage":{}}"#.utf8).write(to: file)
        let storage = ExtensionStorage(directory: directory, oauth: ExtensionOAuthKeychain(store: tokens))
        try storage.setOAuthTokens(extension: "legacy-empty", provider: "", tokens: dummy)
        storage.setLocalStorage(extension: "legacy-empty", key: "new", value: .bool(true))
        storage.flush()
        expect(!String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("oauthTokens"),
               "an empty legacy section safely disappears")
    }

    private static func uninstall(_ directory: URL) throws {
        let tokens = MockTokens()
        tokens.values = ["victim": dummy, "victim:one": dummy, "victim:two": dummy,
                         "victim-other": dummy, "other:victim": dummy]
        let storage = ExtensionStorage(directory: directory, oauth: ExtensionOAuthKeychain(store: tokens))
        storage.setLocalStorage(extension: "victim", key: "saved", value: .bool(true))
        storage.flush()
        let file = directory.appendingPathComponent("victim.json")
        let original = try Data(contentsOf: file)
        tokens.failure = "list"
        expectError("uninstall stops when Keychain lookup fails") { try storage.removeAll(extension: "victim") }
        expect(try Data(contentsOf: file) == original, "lookup failure preserves extension file")
        expect(tokens.values.count == 5, "lookup failure preserves all token accounts")
        tokens.failure = "remove"
        expectError("uninstall reports Keychain deletion failure") { try storage.removeAll(extension: "victim") }
        expect(try Data(contentsOf: file) == original, "deletion failure preserves extension file")
        tokens.failure = nil
        // A pending ordinary write must not resurrect the file after uninstall.
        storage.setLocalStorage(extension: "victim", key: "pending", value: .bool(true))
        try storage.removeAll(extension: "victim")
        storage.flush()
        expect(!FileManager.default.fileExists(atPath: file.path), "uninstall removes ordinary data permanently")
        expect(tokens.values.keys.sorted() == ["other:victim", "victim-other"], "uninstall removes only own accounts")
    }
}
