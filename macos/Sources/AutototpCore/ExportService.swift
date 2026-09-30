import Foundation

/// Writes accounts as `otpauth://` URIs – the format this app, the Windows version,
/// 2FAS, Aegis and other authenticators can read back.
public enum ExportService {
    public struct Entry {
        public let account: TotpAccount
        public let secret: String

        public init(account: TotpAccount, secret: String) {
            self.account = account
            self.secret = secret
        }
    }

    /// Custom parameter so the window-title match survives an export/import round trip.
    public static let matchParameter = "autototp_match"

    public static func uri(for entry: Entry) -> String {
        let account = entry.account
        let issuer = account.issuer.trimmingCharacters(in: .whitespaces)
        let login = account.accountLogin.trimmingCharacters(in: .whitespaces)
        let name = account.displayName

        let label = [issuer, login.isEmpty ? name : login]
            .filter { !$0.isEmpty }
            .map(encode)
            .joined(separator: ":")

        var query = [
            "secret=\(encode(TOTP.normalizeSecret(entry.secret)))",
        ]
        if !issuer.isEmpty {
            query.append("issuer=\(encode(issuer))")
        }
        if account.algorithm.uppercased() != "SHA1" {
            query.append("algorithm=\(encode(account.algorithm.uppercased()))")
        }
        if account.digits != 6 {
            query.append("digits=\(account.digits)")
        }
        if account.period != 30 {
            query.append("period=\(account.period)")
        }
        let match = account.windowTitleMatch.trimmingCharacters(in: .whitespaces)
        if !match.isEmpty && match != issuer {
            query.append("\(matchParameter)=\(encode(match))")
        }
        return "otpauth://totp/\(label)?\(query.joined(separator: "&"))"
    }

    /// Complete file: a short comment header (import skips `#` lines) plus one URI per account.
    public static func file(for entries: [Entry], date: Date = Date()) -> String {
        let stamp = ISO8601DateFormatter().string(from: date)
        var lines = [
            "# Autototp-Export \(stamp)",
            "# \(entries.count) \(entries.count == 1 ? "Account" : "Accounts"). Achtung: Die Secrets stehen hier im Klartext.",
            "# Import in Autototp: Importieren … → otpauth://-Links → Inhalt einfügen.",
            "",
        ]
        lines.append(contentsOf: entries.map(uri(for:)))
        return lines.joined(separator: "\n") + "\n"
    }

    public static func suggestedFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "autototp-export-\(formatter.string(from: date)).txt"
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
