import Foundation
import Security

protocol CredentialStoring: Sendable {
    func load<T: Decodable & Sendable>(_ type: T.Type, account: String) throws -> T?
    func save<T: Encodable & Sendable>(_ value: T, account: String) throws
    func delete(account: String) throws
}

/// Stores OAuth credentials and tokens as generic-password items in the user's
/// macOS Keychain. A stable Developer ID signature and bundle identifier let
/// macOS recognize subsequent builds without repeatedly requesting access.
struct KeychainCredentialStore: CredentialStoring, @unchecked Sendable {
    private let service: String
    private let legacyDirectory: URL

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.digitaltableteur.ringstats",
        legacyDirectory: URL? = nil
    ) {
        self.service = service
        self.legacyDirectory = legacyDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("Ring Stats Public", isDirectory: true)
            .appendingPathComponent("Legacy Secrets", isDirectory: true)
    }

    func load<T: Decodable & Sendable>(_ type: T.Type, account: String) throws -> T? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return try migrateLegacyItem(type, account: account)
        }
        try check(status, operation: "read")
        guard let data = result as? Data else { throw KeychainStoreError.invalidData }
        return try JSONDecoder().decode(type, from: data)
    }

    func save<T: Encodable & Sendable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        try save(data, account: account)
    }

    private func save(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            try check(SecItemAdd(item as CFDictionary, nil), operation: "save")
        } else {
            try check(updateStatus, operation: "update")
        }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status != errSecItemNotFound {
            try check(status, operation: "delete")
        }
        try deleteLegacyItem(account: account)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == errSecSuccess else {
            throw KeychainStoreError.operationFailed(
                operation: operation,
                status: status,
                message: SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
            )
        }
    }

    private func migrateLegacyItem<T: Decodable & Sendable>(
        _ type: T.Type,
        account: String
    ) throws -> T? {
        let file = legacyFileURL(account: account)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        let value = try JSONDecoder().decode(type, from: data)
        try save(data, account: account)
        try deleteLegacyItem(account: account)
        return value
    }

    private func deleteLegacyItem(account: String) throws {
        let file = legacyFileURL(account: account)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        guard FileManager.default.fileExists(atPath: legacyDirectory.path) else { return }
        if try FileManager.default.contentsOfDirectory(atPath: legacyDirectory.path).isEmpty {
            try FileManager.default.removeItem(at: legacyDirectory)
        }
    }

    private func legacyFileURL(account: String) -> URL {
        let safeName = account.replacingOccurrences(
            of: "[^A-Za-z0-9._-]",
            with: "_",
            options: .regularExpression
        )
        return legacyDirectory.appendingPathComponent("\(safeName).json")
    }
}

enum KeychainStoreError: LocalizedError, Sendable {
    case invalidData
    case operationFailed(operation: String, status: OSStatus, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            "The saved Keychain item did not contain valid data."
        case .operationFailed(let operation, let status, let message):
            "Could not \(operation) the Keychain item (\(status)): \(message)"
        }
    }
}
