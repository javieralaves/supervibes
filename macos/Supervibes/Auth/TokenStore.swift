import Foundation
import Security

/// Where the app keeps its session token, one per server (localhost and production are separate).
protocol TokenStore: Sendable {
    func read() -> String?
    func write(_ token: String) throws
    func delete()
}

enum TokenStores {
    /// Release builds use the Keychain. Debug builds are signed ad hoc, and every rebuild changes
    /// the signature, so the Keychain would ask for permission after each build; they keep the
    /// token in a file only you can read instead.
    static func forServer(_ baseURL: URL) -> any TokenStore {
        let account = baseURL.host() ?? "default"
        #if DEBUG
        return FileTokenStore(account: account)
        #else
        return KeychainTokenStore(account: account)
        #endif
    }
}

struct KeychainTokenStore: TokenStore {
    let account: String
    private let service = "com.supervibes.mac.session"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func read() -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ token: String) throws {
        delete()
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

struct FileTokenStore: TokenStore {
    let account: String

    private var url: URL {
        URL.applicationSupportDirectory
            .appending(path: "Supervibes", directoryHint: .isDirectory)
            .appending(path: "dev-session-\(account)")
    }

    func read() -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    func write(_ token: String) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(token.utf8).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
