import AppKit
import AutototpCore
import Combine
import SwiftUI

/// One account plus its decrypted secret and logo, as shown in lists.
struct AccountItem: Identifiable, Equatable {
    var model: TotpAccount
    var secret: String?
    var logo: NSImage?

    var id: UUID { model.id }
    var name: String { model.displayName }
    var login: String { model.accountLogin.trimmingCharacters(in: .whitespaces) }
    var issuer: String { model.issuer.trimmingCharacters(in: .whitespaces) }

    /// "GitHub · Match: GitHub" – issuer is omitted when it just repeats the name.
    var detail: String {
        var parts: [String] = []
        if !issuer.isEmpty && issuer.caseInsensitiveCompare(name) != .orderedSame {
            parts.append(issuer)
        }
        let match = model.windowTitleMatch.trimmingCharacters(in: .whitespaces)
        if !match.isEmpty {
            parts.append("Match: \(match)")
        }
        return parts.isEmpty ? "Kein Fenstertitel-Match" : parts.joined(separator: " · ")
    }

    func code(at date: Date = Date()) -> String? {
        guard let secret else {
            return nil
        }
        return TOTP.code(secret: secret, digits: model.digits, period: model.period, algorithm: model.algorithm, date: date)
    }

    func matches(filter: String) -> Bool {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            return true
        }
        return [name, login, issuer, model.windowTitleMatch].contains {
            $0.localizedCaseInsensitiveContains(query)
        }
    }

    static func == (lhs: AccountItem, rhs: AccountItem) -> Bool {
        lhs.model == rhs.model && lhs.secret == rhs.secret && lhs.logo === rhs.logo
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var items: [AccountItem] = []
    @Published private(set) var settings = AppSettings()
    @Published var accessibilityTrusted = AXIsProcessTrusted()
    @Published var hotkeyRegistered = false
    /// Sheet on the main window; also set from the menu bar (⌘N, ⌘I).
    @Published var sheet: MainSheet?

    let store: AccountStore
    private let box: SecretBox
    private var data = StoredData()
    private var trustTimer: Timer?

    init(store: AccountStore, box: SecretBox) throws {
        self.store = store
        self.box = box
        data = try store.load()
        reloadItems()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                if trusted != self.accessibilityTrusted {
                    self.accessibilityTrusted = trusted
                }
            }
        }
    }

    /// Preview/screenshot model with in-memory data only.
    init(preview items: [AccountItem]) {
        store = AccountStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("autototp-preview"))
        box = SecretBox(key: .init(size: .bits256))
        self.items = items
        accessibilityTrusted = true
        hotkeyRegistered = true
    }

    var accounts: [TotpAccount] { data.accounts }

    func item(_ id: UUID) -> AccountItem? {
        items.first { $0.id == id }
    }

    // MARK: Settings

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        change(&data.settings)
        settings = data.settings
        persist()
    }

    // MARK: Accounts

    func upsert(_ account: TotpAccount, secret: String, newLogo: NSImage?, clearLogo: Bool) throws {
        var account = account
        account.encryptedSecret = try box.seal(TOTP.normalizeSecret(secret))

        let previousLogo = data.accounts.first { $0.id == account.id }?.logoFileName
        if clearLogo {
            account.logoFileName = nil
        } else if let newLogo {
            account.logoFileName = try LogoStore.save(newLogo, for: account.id, in: store.logosDirectory)
        } else {
            account.logoFileName = previousLogo
        }
        if let previousLogo, previousLogo != account.logoFileName {
            LogoStore.delete(previousLogo, in: store.logosDirectory)
        }

        if let index = data.accounts.firstIndex(where: { $0.id == account.id }) {
            data.accounts[index] = account
        } else {
            data.accounts.append(account)
        }
        persist()
        reloadItems()
    }

    func importAccounts(_ imported: [ImportedAccount]) throws {
        for item in imported where item.isSelected {
            var account = TotpAccount()
            account.name = item.name.trimmingCharacters(in: .whitespaces)
            account.accountLogin = item.accountLogin.trimmingCharacters(in: .whitespaces)
            account.issuer = item.issuer.trimmingCharacters(in: .whitespaces)
            account.windowTitleMatch = item.windowTitleMatch.trimmingCharacters(in: .whitespaces)
            account.encryptedSecret = try box.seal(TOTP.normalizeSecret(item.secret))
            account.digits = item.digits
            account.period = item.period
            account.algorithm = item.algorithm
            data.accounts.append(account)
        }
        persist()
        reloadItems()
    }

    func delete(_ id: UUID) {
        if let logo = data.accounts.first(where: { $0.id == id })?.logoFileName {
            LogoStore.delete(logo, in: store.logosDirectory)
        }
        data.accounts.removeAll { $0.id == id }
        persist()
        reloadItems()
    }

    func isKnownSecret(_ secret: String) -> Bool {
        let normalized = TOTP.normalizeSecret(secret)
        return items.contains { $0.secret == normalized }
    }

    func copyCode(_ item: AccountItem) {
        guard let code = item.code() else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
    }

    // MARK: Private

    private func reloadItems() {
        settings = data.settings
        items = data.accounts
            .map { account in
                AccountItem(
                    model: account,
                    secret: box.open(account.encryptedSecret),
                    logo: LogoStore.load(account.logoFileName, in: store.logosDirectory)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func persist() {
        do {
            try store.save(data)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Speichern fehlgeschlagen"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
