import Foundation
import Security

public enum KeychainSessionStoreError: Error {
    case encodeFailed
    case decodeFailed
    case unexpectedStatus(OSStatus)
}

public final class KeychainSessionStore: @unchecked Sendable {
    private let service: String
    private let account: String

    public init(service: String = "de.papa.vokabelapp.google", account: String = "google-session") {
        self.service = service
        self.account = account
    }

    public func save(_ session: AuthSession) throws {
        guard let data = try? JSONEncoder().encode(session) else {
            throw KeychainSessionStoreError.encodeFailed
        }

        let query = baseQuery()
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainSessionStoreError.unexpectedStatus(status)
        }
    }

    public func load() throws -> AuthSession? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainSessionStoreError.unexpectedStatus(status)
        }

        guard let data = item as? Data,
              let session = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            throw KeychainSessionStoreError.decodeFailed
        }

        return session
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSessionStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
