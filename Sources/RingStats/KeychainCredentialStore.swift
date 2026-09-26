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
        do {
            if let data = try readData(account: account, useDataProtectionKeychain: true) {
                let value = try JSONDecoder().decode(type, from: data)
                // A previous migration may have written the protected copy and
                // then failed before removing a weaker source. Retry cleanup on
                // every successful preferred read so duplicate secrets do not
                // persist indefinitely.
                try? deleteKeychainItem(account: account, useDataProtectionKeychain: false)
                try? deleteLegacyItem(account: account)
                return value
            }
        } catch where isMissingEntitlement(error) {
            // Unsandboxed command-line builds and older signed builds may not
            // carry the entitlement required by the data-protection Keychain.
            // Preserve access to their existing classic-Keychain items.
            if let data = try readData(account: account, useDataProtectionKeychain: false) {
                let value = try JSONDecoder().decode(type, from: data)
                // A prior plaintext migration may have saved this compatible
                // Keychain copy before deletion of the source file failed.
                // Retry that cleanup on every successful read.
                try? deleteLegacyItem(account: account)
                return value
            }
            return try migrateLegacyItem(type, account: account)
        }

        // Builds predating the data-protection Keychain flag may have written to
        // the legacy file-based Keychain. Move those items once, then remove the
        // weaker copy. The app's JSON-file migration remains as a final fallback.
        if let legacyData = try readData(account: account, useDataProtectionKeychain: false) {
            let value = try JSONDecoder().decode(type, from: legacyData)
            do {
                // Delete the compatible copy only after the protected write
                // succeeds. Unsandboxed/older builds keep using that copy.
                try save(legacyData, account: account, useDataProtectionKeychain: true)
                try? deleteKeychainItem(account: account, useDataProtectionKeychain: false)
            } catch {
                // The compatible Keychain item remains authoritative. Retry
                // migration on a later read without blocking app access.
            }
            try? deleteLegacyItem(account: account)
            return value
        }

        return try migrateLegacyItem(type, account: account)
    }

    func save<T: Encodable & Sendable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        try save(data, account: account)
    }

    private func save(_ data: Data, account: String) throws {
        do {
            try save(data, account: account, useDataProtectionKeychain: true)
        } catch where isMissingEntitlement(error) {
            try save(data, account: account, useDataProtectionKeychain: false)
        }
    }

    private func save(
        _ data: Data,
        account: String,
        useDataProtectionKeychain: Bool
    ) throws {
        let query = baseQuery(
            account: account,
            useDataProtectionKeychain: useDataProtectionKeychain
        )
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
        do {
            try deleteKeychainItem(account: account, useDataProtectionKeychain: true)
        } catch where isMissingEntitlement(error) {
            // Continue with the compatible Keychain and legacy-file cleanup.
        }
        try deleteKeychainItem(account: account, useDataProtectionKeychain: false)
        try deleteLegacyItem(account: account)
    }

    private func baseQuery(
        account: String,
        useDataProtectionKeychain: Bool = true
    ) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: useDataProtectionKeychain,
        ]
    }

    private func readData(
        account: String,
        useDataProtectionKeychain: Bool
    ) throws -> Data? {
        var query = baseQuery(
            account: account,
            useDataProtectionKeychain: useDataProtectionKeychain
        )
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status, operation: "read")
        guard let data = result as? Data else { throw KeychainStoreError.invalidData }
        return data
    }

    private func deleteKeychainItem(
        account: String,
        useDataProtectionKeychain: Bool
    ) throws {
        let status = SecItemDelete(
            baseQuery(
                account: account,
                useDataProtectionKeychain: useDataProtectionKeychain
            ) as CFDictionary
        )
        if status != errSecItemNotFound {
            try check(status, operation: "delete")
        }
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

    private func isMissingEntitlement(_ error: any Error) -> Bool {
        guard case KeychainStoreError.operationFailed(_, let status, _) = error else {
            return false
        }
        return status == errSecMissingEntitlement
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
