import CommonCrypto
import CryptoKit
import Foundation

public struct ImportedAccount: Identifiable, Equatable {
    public let id = UUID()
    public var name = ""
    public var accountLogin = ""
    public var issuer = ""
    public var secret = ""
    public var windowTitleMatch = ""
    public var digits = 6
    public var period = 30
    public var algorithm = "SHA1"
    public var isSelected = true
    /// Set by the caller when the secret already exists in the store.
    public var isDuplicate = false

    public init() {}
}

public struct ImportResult {
    public var accounts: [ImportedAccount] = []
    public var warnings: [String] = []

    public init() {}
}

public enum ImportError: LocalizedError, Equatable {
    case passwordRequired
    case wrongPassword
    case unknownEncryptedFormat
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .passwordRequired:
            return "Diese 2FAS-Sicherung ist passwortgeschützt. Bitte das Backup-Passwort eingeben."
        case .wrongPassword:
            return "Das 2FAS-Backup konnte nicht entschlüsselt werden. Ist das Passwort richtig?"
        case .unknownEncryptedFormat:
            return "Das verschlüsselte 2FAS-Format wird nicht erkannt."
        case .invalidJSON:
            return "Die Datei ist kein gültiges 2FAS-Backup."
        }
    }
}

public enum ImportService {
    // MARK: otpauth://

    public static func parseOtpAuthText(_ text: String) -> ImportResult {
        var result = ImportResult()
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            guard line.lowercased().hasPrefix("otpauth://") else {
                result.warnings.append("Übersprungen (kein otpauth://): \(trimForDisplay(line))")
                continue
            }
            switch parseOtpAuthURI(line) {
            case .success(let account):
                result.accounts.append(account)
            case .failure(let warning):
                result.warnings.append(warning.message)
            }
        }

        if result.accounts.isEmpty && result.warnings.isEmpty {
            result.warnings.append("Keine otpauth:// URIs gefunden.")
        }
        return result
    }

    public struct Warning: Error {
        public let message: String
    }

    public static func parseOtpAuthURI(_ uri: String) -> Result<ImportedAccount, Warning> {
        let escaped = uri.replacingOccurrences(of: " ", with: "%20")
        guard let components = URLComponents(string: escaped),
              components.scheme?.lowercased() == "otpauth" else {
            return .failure(Warning(message: "Ungültige otpauth:// URI."))
        }

        let type = components.host ?? ""
        guard type.lowercased() == "totp" else {
            return .failure(Warning(message: "Übersprungen (\(type), nur TOTP wird unterstützt): \(trimForDisplay(uri))"))
        }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name.lowercased()] = item.value ?? ""
        }

        guard let rawSecret = query["secret"], !rawSecret.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure(Warning(message: "otpauth:// URI ohne Secret."))
        }
        let secret = TOTP.normalizeSecret(rawSecret)
        guard TOTP.validationError(secret) == nil else {
            return .failure(Warning(message: "Ungültiges Secret in URI: \(trimForDisplay(uri))"))
        }

        let label = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var labelIssuer = ""
        var labelAccount = label
        if let colon = label.firstIndex(of: ":"), colon != label.startIndex {
            labelIssuer = String(label[..<colon])
            labelAccount = String(label[label.index(after: colon)...])
        }

        let issuer = firstNonEmpty(query["issuer"], labelIssuer)
        var account = ImportedAccount()
        account.name = firstNonEmpty(labelAccount, label, issuer, "Account")
        account.accountLogin = labelAccount.trimmingCharacters(in: .whitespaces)
        account.issuer = issuer
        account.secret = secret
        account.windowTitleMatch = issuer
        account.digits = Int(query["digits"] ?? "") ?? 6
        account.period = Int(query["period"] ?? "") ?? 30
        account.algorithm = (query["algorithm"] ?? "SHA1").uppercased()
        return .success(account)
    }

    // MARK: 2FAS

    public static func parse2FasJSON(_ data: Data, password: String?) throws -> ImportResult {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ImportError.invalidJSON
        }

        var services = root["services"] as? [[String: Any]] ?? []
        if services.isEmpty,
           let encrypted = root["servicesEncrypted"] as? String,
           !encrypted.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let password, !password.isEmpty else {
                throw ImportError.passwordRequired
            }
            let plain = try decrypt2FasServices(encrypted, password: password)
            guard let decoded = (try? JSONSerialization.jsonObject(with: plain)) as? [[String: Any]] else {
                throw ImportError.wrongPassword
            }
            services = decoded
        }

        var result = ImportResult()
        guard !services.isEmpty else {
            result.warnings.append("Die 2FAS-Datei enthält keine Services.")
            return result
        }

        for service in services {
            switch map2FasService(service) {
            case .success(let account):
                result.accounts.append(account)
            case .failure(let warning):
                result.warnings.append(warning.message)
            }
        }
        return result
    }

    /// Whether a 2FAS file needs a password before it can be parsed.
    public static func is2FasEncrypted(_ data: Data) -> Bool {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return false
        }
        let services = root["services"] as? [Any] ?? []
        return services.isEmpty && (root["servicesEncrypted"] as? String)?.isEmpty == false
    }

    static func map2FasService(_ service: [String: Any]) -> Result<ImportedAccount, Warning> {
        let otp = service["otp"] as? [String: Any] ?? [:]
        let serviceName = string(service, "name")
        let tokenType = string(otp, "tokenType")
        if !tokenType.isEmpty && tokenType.uppercased() != "TOTP" {
            return .failure(Warning(message: "Übersprungen (\(tokenType)): \(serviceName)"))
        }

        let secret = TOTP.normalizeSecret(string(service, "secret"))
        guard TOTP.validationError(secret) == nil else {
            return .failure(Warning(message: "Ungültiges Secret: \(serviceName)"))
        }

        let name = firstNonEmpty(serviceName, string(otp, "account"), string(otp, "issuer"), "Account")
        var account = ImportedAccount()
        account.name = name
        account.accountLogin = firstNonEmpty(string(otp, "account"), string(service, "account"))
        account.issuer = firstNonEmpty(string(otp, "issuer"), name)
        account.secret = secret
        account.windowTitleMatch = account.issuer
        account.digits = int(otp, "digits") ?? 6
        account.period = int(otp, "period") ?? 30
        account.algorithm = firstNonEmpty(string(otp, "algorithm"), "SHA1").uppercased()
        return .success(account)
    }

    /// 2FAS stores `base64(cipher+tag):base64(salt):base64(iv)`, PBKDF2-SHA256 (10k) + AES-256-GCM.
    /// AES-CBC is tried as a fallback for older exports.
    static func decrypt2FasServices(_ encrypted: String, password: String) throws -> Data {
        let parts = encrypted.split(separator: ":").map(String.init)
        guard parts.count >= 3,
              let cipher = Data(base64Encoded: parts[0]),
              let salt = Data(base64Encoded: parts[1]),
              let iv = Data(base64Encoded: parts[2]) else {
            throw ImportError.unknownEncryptedFormat
        }

        let key = pbkdf2SHA256(password: password, salt: salt, iterations: 10_000, length: 32)

        if cipher.count > 16,
           let nonce = try? AES.GCM.Nonce(data: iv),
           let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: cipher.dropLast(16), tag: cipher.suffix(16)),
           let plain = try? AES.GCM.open(box, using: SymmetricKey(data: key)) {
            return plain
        }

        if iv.count == kCCBlockSizeAES128, let plain = aesCBCDecrypt(cipher, key: key, iv: iv) {
            return plain
        }
        throw ImportError.wrongPassword
    }

    static func pbkdf2SHA256(password: String, salt: Data, iterations: Int, length: Int) -> Data {
        var derived = Data(count: length)
        let passwordBytes = Array(password.utf8)
        _ = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.map { Int8(bitPattern: $0) },
                    passwordBytes.count,
                    saltPtr.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    derivedPtr.bindMemory(to: UInt8.self).baseAddress,
                    length
                )
            }
        }
        return derived
    }

    static func aesCBCDecrypt(_ cipher: Data, key: Data, iv: Data) -> Data? {
        var output = Data(count: cipher.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var moved = 0
        let status = output.withUnsafeMutableBytes { outPtr in
            cipher.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            inPtr.baseAddress, cipher.count,
                            outPtr.baseAddress, outputCapacity,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            return nil
        }
        return output.prefix(moved)
    }

    // MARK: Helpers

    private static func string(_ dict: [String: Any], _ key: String) -> String {
        (dict[key] as? String) ?? ""
    }

    private static func int(_ dict: [String: Any], _ key: String) -> Int? {
        if let number = dict[key] as? Int {
            return number
        }
        if let text = dict[key] as? String {
            return Int(text)
        }
        return nil
    }

    static func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            if let trimmed = value?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    static func trimForDisplay(_ text: String) -> String {
        text.count <= 48 ? text : String(text.prefix(45)) + "..."
    }
}
