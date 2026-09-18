import Foundation

public enum MatchKind: Equatable {
    case windowTitle
    case name
    case issuer
}

public struct AccountMatch: Equatable {
    public let account: TotpAccount
    public let kind: MatchKind

    public var label: String {
        switch kind {
        case .windowTitle:
            let match = account.windowTitleMatch.trimmingCharacters(in: .whitespaces)
            return match.isEmpty ? "Fenstertitel" : "Match: \(match)"
        case .name:
            return "Name: \(account.name.trimmingCharacters(in: .whitespaces))"
        case .issuer:
            return "Aussteller: \(account.issuer.trimmingCharacters(in: .whitespaces))"
        }
    }
}

/// Same matching rules as the Windows app's AutoFillService.
public enum WindowMatcher {
    /// Explicit window-title matches win; name/issuer hits are only used when none exist.
    public static func findMatches(_ accounts: [TotpAccount], windowTitle: String) -> [AccountMatch] {
        guard !windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        var titleMatches: [AccountMatch] = []
        var fallbacks: [AccountMatch] = []
        for account in accounts {
            if !account.windowTitleMatch.trimmingCharacters(in: .whitespaces).isEmpty,
               matches(windowTitle: windowTitle, candidate: account.windowTitleMatch) {
                titleMatches.append(AccountMatch(account: account, kind: .windowTitle))
            } else if matches(windowTitle: windowTitle, candidate: account.name) {
                fallbacks.append(AccountMatch(account: account, kind: .name))
            } else if matches(windowTitle: windowTitle, candidate: account.issuer) {
                fallbacks.append(AccountMatch(account: account, kind: .issuer))
            }
        }
        return titleMatches.isEmpty ? fallbacks : titleMatches
    }

    /// Case-insensitive contains after trim; punctuation and extra spaces are ignored.
    /// Also matches compact forms so "ANG CH" hits "ANG-CH" or "ANGCH".
    public static func matches(windowTitle: String, candidate: String) -> Bool {
        let titleNorm = normalize(windowTitle)
        let candidateNorm = normalize(candidate)
        guard !titleNorm.isEmpty, !candidateNorm.isEmpty else {
            return false
        }

        if containsNormalized(titleNorm, candidateNorm) {
            return true
        }

        let titleCompact = titleNorm.replacingOccurrences(of: " ", with: "")
        let candidateCompact = candidateNorm.replacingOccurrences(of: " ", with: "")
        return candidateCompact.count >= 2 && containsNormalized(titleCompact, candidateCompact)
    }

    static func containsNormalized(_ haystack: String, _ needle: String) -> Bool {
        if haystack.contains(needle) {
            return true
        }
        return haystack.count >= 3 && needle.contains(haystack)
    }

    static func normalize(_ value: String) -> String {
        var result = ""
        var pendingSpace = false
        for ch in value.trimmingCharacters(in: .whitespacesAndNewlines) {
            if ch.isLetter || ch.isNumber {
                if pendingSpace && !result.isEmpty {
                    result.append(" ")
                }
                result.append(contentsOf: ch.lowercased())
                pendingSpace = false
            } else {
                pendingSpace = true
            }
        }
        return result
    }
}
