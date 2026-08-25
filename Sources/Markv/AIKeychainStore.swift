import Foundation
import Security

protocol AIAPIKeyStoring {
    func loadAPIKey() throws -> String
    func saveAPIKey(_ value: String) throws
}

enum AIKeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            "Keychain operation failed (\(status))."
        }
    }
}

final class AIKeychainStore: AIAPIKeyStoring {
    private let service = "io.markv.app.ai"
    private let account = "openai-compatible-api-key"

    func loadAPIKey() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw AIKeychainError.unexpectedStatus(status)
        }
        return value
    }

    func saveAPIKey(_ value: String) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let status = SecItemDelete(lookup as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw AIKeychainError.unexpectedStatus(status)
            }
            return
        }

        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AIKeychainError.unexpectedStatus(updateStatus)
        }

        var item = lookup
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AIKeychainError.unexpectedStatus(addStatus)
        }
    }
}
