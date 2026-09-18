import CryptoKit
import Foundation

struct TOTPTests {
    // RFC 6238 Appendix B, 8 digits.
    let sha1Secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" // "12345678901234567890"

    func rfc6238SHA1() {
        expect(TOTP.code(secret: sha1Secret, digits: 8, date: Date(timeIntervalSince1970: 59)) == "94287082")
        expect(TOTP.code(secret: sha1Secret, digits: 8, date: Date(timeIntervalSince1970: 1_111_111_109)) == "07081804")
        expect(TOTP.code(secret: sha1Secret, digits: 8, date: Date(timeIntervalSince1970: 20_000_000_000)) == "65353130")
    }

    func rfc6238SHA256AndSHA512() {
        let sha256 = base32(Data("12345678901234567890123456789012".utf8))
        let sha512 = base32(Data("1234567890123456789012345678901234567890123456789012345678901234".utf8))
        expect(TOTP.code(secret: sha256, digits: 8, algorithm: "SHA256", date: Date(timeIntervalSince1970: 59)) == "46119246")
        expect(TOTP.code(secret: sha512, digits: 8, algorithm: "SHA512", date: Date(timeIntervalSince1970: 59)) == "90693936")
    }

    func normalizesAndValidates() {
        expect(TOTP.normalizeSecret("jbsw y3dp-ehpk 3pxp") == "JBSWY3DPEHPK3PXP")
        expect(TOTP.validationError("JBSWY3DPEHPK3PXP") == nil)
        expect(TOTP.validationError("ABC") == "Das Secret ist zu kurz.")
        expect(TOTP.validationError("JBSWY3DP1HPK3PXP") == "Das Secret ist kein gültiges Base32.")
    }

    func formatsCodes() {
        expect(TOTP.format("482193") == "482 193")
        expect(TOTP.format("94287082") == "94287082")
    }

    func remainingSeconds() {
        expect(TOTP.remainingSeconds(date: Date(timeIntervalSince1970: 60)) == 30)
        expect(TOTP.remainingSeconds(date: Date(timeIntervalSince1970: 71.5)) == 19)
    }

    private func base32(_ data: Data) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var output = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[(buffer >> bits) & 31])
            }
        }
        if bits > 0 {
            output.append(alphabet[(buffer << (5 - bits)) & 31])
        }
        return output
    }
}

struct WindowMatcherTests {
    func account(_ name: String, issuer: String = "", match: String = "") -> TotpAccount {
        var account = TotpAccount()
        account.name = name
        account.issuer = issuer
        account.windowTitleMatch = match
        return account
    }

    func ignoresCaseAndPunctuation() {
        expect(WindowMatcher.matches(windowTitle: "Viscosity – Verbinden", candidate: "viscosity"))
        expect(WindowMatcher.matches(windowTitle: "Login ANG-CH Portal", candidate: "ANG CH"))
        expect(WindowMatcher.matches(windowTitle: "Login ANGCH Portal", candidate: "ANG CH"))
        expect(!WindowMatcher.matches(windowTitle: "GitLab", candidate: "GitHub"))
        expect(!WindowMatcher.matches(windowTitle: "", candidate: "GitHub"))
    }

    func windowTitleMatchWinsOverNameFallback() {
        let accounts = [
            account("GitHub — rolf", issuer: "GitHub"),
            account("Stooss VPN", issuer: "Stooss", match: "Stooss Remote"),
            account("Stooss Mail", issuer: "Stooss"),
        ]
        let matches = WindowMatcher.findMatches(accounts, windowTitle: "Stooss Remote Access – Safari")
        expect(matches.map(\.account.name) == ["Stooss VPN"])
        expect(matches.first?.kind == .windowTitle)
    }

    func fallsBackToNameAndIssuer() {
        let accounts = [account("GitHub", issuer: "GitHub"), account("Work", issuer: "Microsoft")]
        let matches = WindowMatcher.findMatches(accounts, windowTitle: "Sign in to your Microsoft account")
        expect(matches.map(\.account.name) == ["Work"])
        expect(matches.first?.kind == .issuer)
    }
}

struct ImportTests {
    func parsesOtpAuthLines() {
        let text = """
        otpauth://totp/GitHub:rolf?secret=JBSWY3DPEHPK3PXP&issuer=GitHub
        # comment
        otpauth://hotp/Old?secret=JBSWY3DPEHPK3PXP
        otpauth://totp/Microsoft:rolf@outlook.com?secret=KRSXG5A3PEHPK3PX&issuer=Microsoft&digits=8&algorithm=sha256
        not a uri
        """
        let result = ImportService.parseOtpAuthText(text)
        expect(result.accounts.count == 2)
        expect(result.accounts[0].name == "rolf")
        expect(result.accounts[0].issuer == "GitHub")
        expect(result.accounts[0].windowTitleMatch == "GitHub")
        expect(result.accounts[1].accountLogin == "rolf@outlook.com")
        expect(result.accounts[1].digits == 8)
        expect(result.accounts[1].algorithm == "SHA256")
        expect(result.warnings.count == 2)
    }

    func parsesPlain2Fas() throws {
        let json = """
        {"services":[{"name":"GitHub","secret":"JBSWY3DPEHPK3PXP","otp":{"account":"rolf","issuer":"GitHub","digits":6,"period":30,"algorithm":"SHA1","tokenType":"TOTP"}},
                     {"name":"Steam","secret":"JBSWY3DPEHPK3PXP","otp":{"tokenType":"STEAM"}}]}
        """
        let result = try ImportService.parse2FasJSON(Data(json.utf8), password: nil)
        expect(result.accounts.map(\.name) == ["GitHub"])
        expect(result.accounts[0].accountLogin == "rolf")
        expect(result.warnings.count == 1)
    }

    func decryptsEncrypted2Fas() throws {
        let services = #"[{"name":"GitHub","secret":"JBSWY3DPEHPK3PXP","otp":{"issuer":"GitHub"}}]"#
        let salt = Data((0..<256).map { UInt8($0 % 251) })
        let iv = Data((0..<12).map { UInt8($0) })
        let key = ImportService.pbkdf2SHA256(password: "geheim", salt: salt, iterations: 10_000, length: 32)
        let box = try AES.GCM.seal(Data(services.utf8), using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: iv))
        let encrypted = [box.ciphertext + box.tag, salt, iv].map { $0.base64EncodedString() }.joined(separator: ":")
        let json = Data(#"{"services":[],"servicesEncrypted":"\#(encrypted)"}"#.utf8)

        expect(ImportService.is2FasEncrypted(json))
        expectThrows(ImportError.passwordRequired) { _ = try ImportService.parse2FasJSON(json, password: nil) }
        expectThrows(ImportError.wrongPassword) { _ = try ImportService.parse2FasJSON(json, password: "falsch") }
        let result = try ImportService.parse2FasJSON(json, password: "geheim")
        expect(result.accounts.map(\.name) == ["GitHub"])
    }
}

struct StorageTests {
    func secretBoxRoundTrip() throws {
        let box = SecretBox(key: SymmetricKey(size: .bits256))
        let sealed = try box.seal("JBSWY3DPEHPK3PXP")
        expect(!sealed.contains("JBSWY3DPEHPK3PXP"))
        expect(box.open(sealed) == "JBSWY3DPEHPK3PXP")
        expect(SecretBox(key: SymmetricKey(size: .bits256)).open(sealed) == nil)
    }

    func readsWindowsStyleJSONWithMissingFields() throws {
        let json = #"{"version":1,"settings":{"sendEnterAfterCode":false,"hotkeyKey":"T"},"accounts":[{"id":"7d9f7a2e-1c3b-4a5d-9e8f-0a1b2c3d4e5f","name":"GitHub"}]}"#
        let stored = try JSONDecoder().decode(StoredData.self, from: Data(json.utf8))
        expect(stored.settings.sendEnterAfterCode == false)
        expect(stored.accounts.first?.digits == 6)
        expect(stored.accounts.first?.algorithm == "SHA1")
    }

    func storeRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AccountStore(directory: dir)
        let box = try store.makeSecretBox()
        var stored = StoredData()
        var account = TotpAccount()
        account.name = "GitHub"
        account.encryptedSecret = try box.seal("JBSWY3DPEHPK3PXP")
        stored.accounts = [account]
        try store.save(stored)

        let reloaded = try store.load()
        expect(reloaded == stored)
        let reopened = try store.makeSecretBox()
        expect(reopened.open(reloaded.accounts[0].encryptedSecret) == "JBSWY3DPEHPK3PXP")
        try? FileManager.default.removeItem(at: dir)
    }
}
