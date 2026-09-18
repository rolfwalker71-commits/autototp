import Foundation

/// On-disk layout of `accounts.json`. Field names match the Windows app (camelCase),
/// but secrets are sealed with a Keychain key instead of DPAPI, so files are not interchangeable.
public struct StoredData: Codable, Equatable {
    public var version: Int = 1
    public var settings = AppSettings()
    public var accounts: [TotpAccount] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        accounts = try c.decodeIfPresent([TotpAccount].self, forKey: .accounts) ?? []
    }
}

public struct AppSettings: Codable, Equatable {
    public var startMinimized = false
    public var sendEnterAfterCode = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startMinimized = try c.decodeIfPresent(Bool.self, forKey: .startMinimized) ?? false
        sendEnterAfterCode = try c.decodeIfPresent(Bool.self, forKey: .sendEnterAfterCode) ?? true
    }
}

public struct TotpAccount: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name = ""
    /// Login/account from 2FAS `otp.account` or an otpauth label (e.g. email). Shown as second line.
    public var accountLogin = ""
    public var issuer = ""
    /// Preferred match against the foreground window title. Name and issuer are fallbacks.
    public var windowTitleMatch = ""
    /// AES-GCM sealed Base32 secret (Base64 of nonce + ciphertext + tag).
    public var encryptedSecret = ""
    /// File name under `logos/`, or nil for the generated letter tile.
    public var logoFileName: String?
    public var digits = 6
    public var period = 30
    public var algorithm = "SHA1"

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        accountLogin = try c.decodeIfPresent(String.self, forKey: .accountLogin) ?? ""
        issuer = try c.decodeIfPresent(String.self, forKey: .issuer) ?? ""
        windowTitleMatch = try c.decodeIfPresent(String.self, forKey: .windowTitleMatch) ?? ""
        encryptedSecret = try c.decodeIfPresent(String.self, forKey: .encryptedSecret) ?? ""
        logoFileName = try c.decodeIfPresent(String.self, forKey: .logoFileName)
        digits = try c.decodeIfPresent(Int.self, forKey: .digits) ?? 6
        period = try c.decodeIfPresent(Int.self, forKey: .period) ?? 30
        algorithm = try c.decodeIfPresent(String.self, forKey: .algorithm) ?? "SHA1"
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Account" : trimmed
    }
}
