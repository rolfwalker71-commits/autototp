import CryptoKit
import Foundation
import Security

/// Seals TOTP secrets with AES-256-GCM. The key lives in the user's login Keychain,
/// which plays the role DPAPI has on Windows: the file alone is useless on another account or Mac.
public final class SecretBox {
    public enum KeyError: LocalizedError {
        case keychain(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .keychain(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "Status \(status)"
                return "Der Schlüssel im macOS-Schlüsselbund ist nicht verfügbar: \(message)"
            }
        }
    }

    private let key: SymmetricKey

    public init(key: SymmetricKey) {
        self.key = key
    }

    public func seal(_ plaintext: String) throws -> String {
        let box = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        return box.combined!.base64EncodedString()
    }

    public func open(_ sealed: String) -> String? {
        guard let data = Data(base64Encoded: sealed),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key) else {
            return nil
        }
        return String(data: plain, encoding: .utf8)
    }

    // MARK: Key sources

    static let keychainService = "Autototp"
    static let keychainAccount = "secret-encryption-key"

    /// Loads the Keychain key, creating it on first launch. Never replaces an existing key.
    public static func loadOrCreateKeychainKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else {
            throw KeyError.keychain(status)
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrLabel as String: "Autototp – Schlüssel für TOTP-Secrets",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: keyData,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeyError.keychain(addStatus)
        }
        return key
    }

    /// File-based key for development/test data directories (`AUTOTOTP_DATA_DIR`), no Keychain prompts.
    public static func loadOrCreateFileKey(at url: URL) throws -> SymmetricKey {
        if let data = try? Data(contentsOf: url), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        try key.withUnsafeBytes { Data($0) }.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return key
    }
}
