import Foundation

public final class AccountStore {
    public let directory: URL
    public let fileURL: URL
    public let logosDirectory: URL
    /// True when `AUTOTOTP_DATA_DIR` points to a development data directory.
    public let isDevelopmentDirectory: Bool

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
            isDevelopmentDirectory = true
        } else if let override = ProcessInfo.processInfo.environment["AUTOTOTP_DATA_DIR"], !override.isEmpty {
            self.directory = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
            isDevelopmentDirectory = true
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = support.appendingPathComponent("Autototp", isDirectory: true)
            isDevelopmentDirectory = false
        }
        fileURL = self.directory.appendingPathComponent("accounts.json")
        logosDirectory = self.directory.appendingPathComponent("logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: logosDirectory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.directory.path)
    }

    public func load() throws -> StoredData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return StoredData()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(StoredData.self, from: data)
    }

    public func save(_ stored: StoredData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(stored)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func makeSecretBox() throws -> SecretBox {
        if isDevelopmentDirectory {
            return SecretBox(key: try SecretBox.loadOrCreateFileKey(at: directory.appendingPathComponent(".dev-key")))
        }
        return SecretBox(key: try SecretBox.loadOrCreateKeychainKey())
    }
}
