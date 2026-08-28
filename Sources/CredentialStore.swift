import Foundation
import Security

struct Credentials: Equatable {
    var username: String
    var password: String

    static let empty = Credentials(username: "", password: "")

    var isConfigured: Bool {
        !username.isEmpty && !password.isEmpty
    }
}

/// Stores the Easynews password in the Keychain and the username in
/// UserDefaults. Works identically on iOS and macOS.
enum CredentialStore {
    private static let service = "com.easynewsplayer.account"
    private static let usernameKey = "easynews.username"

    static func load() -> Credentials {
        let username = UserDefaults.standard.string(forKey: usernameKey) ?? ""
        guard !username.isEmpty else { return .empty }
        return Credentials(username: username, password: readPassword(for: username) ?? "")
    }

    static func save(_ credentials: Credentials) {
        UserDefaults.standard.set(credentials.username, forKey: usernameKey)
        writePassword(credentials.password, for: credentials.username)
    }

    static func clear() {
        let username = UserDefaults.standard.string(forKey: usernameKey) ?? ""
        if !username.isEmpty {
            SecItemDelete(baseQuery(for: username) as CFDictionary)
        }
        UserDefaults.standard.removeObject(forKey: usernameKey)
    }

    // MARK: - Keychain

    private static func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readPassword(for account: String) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writePassword(_ password: String, for account: String) {
        let query = baseQuery(for: account)
        SecItemDelete(query as CFDictionary)

        guard !password.isEmpty else { return }

        var attributes = query
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
