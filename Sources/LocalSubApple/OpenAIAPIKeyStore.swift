import Foundation
import Security

public enum OpenAIAPIKeyStoreError: Error, LocalizedError, Equatable {
    case emptyKey
    case invalidStoredValue
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .emptyKey:
            "APIキーを入力してください"
        case .invalidStoredValue:
            "保存済みAPIキーを読み取れません"
        case .keychain(let status):
            "APIキーをKeychainで処理できません（\(status)）"
        }
    }
}

public final class OpenAIAPIKeyStore: @unchecked Sendable {
    private let service: String
    private let account = "openai-api-key"

    public init(service: String = "com.byteflare.localsub") {
        self.service = service
    }

    public func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw OpenAIAPIKeyStoreError.keychain(status) }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            throw OpenAIAPIKeyStoreError.invalidStoredValue
        }
        return value
    }

    public func save(_ key: String) throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw OpenAIAPIKeyStoreError.emptyKey }
        let data = Data(normalized.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw OpenAIAPIKeyStoreError.keychain(updateStatus)
        }
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw OpenAIAPIKeyStoreError.keychain(addStatus) }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAIAPIKeyStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}
