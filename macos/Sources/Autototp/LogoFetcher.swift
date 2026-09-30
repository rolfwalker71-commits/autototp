import AppKit
import AutototpCore

/// Fetches a favicon for an account. This sends the guessed domain to an icon service,
/// so it only ever runs when the user asks for it (button in the editor, switch in settings).
enum LogoFetcher {
    /// "rolf@firma.ch" → firma.ch; "Microsoft 365" → microsoft365.com; "github.com" stays.
    static func domain(issuer: String, login: String = "", name: String = "") -> String? {
        if let at = login.firstIndex(of: "@") {
            let host = String(login[login.index(after: at)...]).trimmingCharacters(in: .whitespaces)
            if host.contains("."), !host.hasSuffix(".local") {
                return host.lowercased()
            }
        }
        for candidate in [issuer, name] {
            let trimmed = candidate.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                continue
            }
            if trimmed.contains(".") {
                return trimmed.lowercased()
            }
            let slug = trimmed.lowercased().filter { $0.isLetter || $0.isNumber }
            if slug.count >= 3 {
                return slug + ".com"
            }
        }
        return nil
    }

    static func fetchIcon(domain: String) async -> NSImage? {
        guard let url = URL(string: "https://icons.duckduckgo.com/ip3/\(domain).ico") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data),
              image.isValid,
              image.size.width >= 16 else {
            return nil
        }
        return image
    }

    static func fetchIcon(issuer: String, login: String = "", name: String = "") async -> NSImage? {
        guard let domain = domain(issuer: issuer, login: login, name: name) else {
            return nil
        }
        return await fetchIcon(domain: domain)
    }
}
