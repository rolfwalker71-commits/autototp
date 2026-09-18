import AppKit
import AutototpCore
import SwiftUI
import UniformTypeIdentifiers

struct AccountEditorView: View {
    @ObservedObject var model: AppModel
    let existing: AccountItem?
    var frozenDate: Date?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var login = ""
    @State private var issuer = ""
    @State private var secret = ""
    @State private var match = ""
    @State private var digits = 6
    @State private var period = 30
    @State private var algorithm = "SHA1"
    @State private var showSecret = false
    @State private var newLogo: NSImage?
    @State private var clearLogo = false
    @State private var showAdvanced = false
    @State private var errorMessage: String?

    init(model: AppModel, existing: AccountItem?, frozenDate: Date? = nil) {
        self.model = model
        self.existing = existing
        self.frozenDate = frozenDate
        if let existing {
            _name = State(initialValue: existing.model.name)
            _login = State(initialValue: existing.model.accountLogin)
            _issuer = State(initialValue: existing.model.issuer)
            _secret = State(initialValue: existing.secret ?? "")
            _match = State(initialValue: existing.model.windowTitleMatch)
            _digits = State(initialValue: existing.model.digits)
            _period = State(initialValue: existing.model.period)
            _algorithm = State(initialValue: existing.model.algorithm)
        }
    }

    private var secretError: String? {
        TOTP.normalizeSecret(secret).isEmpty ? nil : TOTP.validationError(secret)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && TOTP.validationError(secret) == nil
    }

    private var currentLogo: NSImage? {
        if clearLogo {
            return nil
        }
        return newLogo ?? existing?.logo
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 14) {
                        LogoTile(name: name.isEmpty ? "?" : name, image: currentLogo, size: 52)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(existing == nil ? "Neuer Account" : "Account bearbeiten")
                                .font(.headline)
                            HStack(spacing: 8) {
                                Button("Logo wählen …", action: chooseLogo)
                                    .controlSize(.small)
                                if currentLogo != nil {
                                    Button("Entfernen") {
                                        newLogo = nil
                                        clearLogo = true
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    TextField("Name", text: $name, prompt: Text("z. B. GitHub"))
                    TextField("Login", text: $login, prompt: Text("optional, z. B. E-Mail"))
                    TextField("Aussteller", text: $issuer, prompt: Text("z. B. GitHub"))
                }

                Section {
                    HStack {
                        Group {
                            if showSecret {
                                TextField("Secret", text: $secret, prompt: Text("Base32"))
                            } else {
                                SecureField("Secret", text: $secret, prompt: Text("Base32"))
                            }
                        }
                        .font(.system(.body, design: .monospaced))
                        Button {
                            showSecret.toggle()
                        } label: {
                            Image(systemName: showSecret ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(showSecret ? "Secret verbergen" : "Secret anzeigen")
                    }
                    TimelineView(.animation(minimumInterval: 0.1, paused: frozenDate != nil)) { context in
                        let now = frozenDate ?? context.date
                        let code = TOTP.validationError(secret) == nil
                            ? TOTP.code(secret: secret, digits: digits, period: period, algorithm: algorithm, date: now)
                            : nil
                        LabeledContent("Aktueller Code") {
                            HStack(spacing: 10) {
                                CodeText(code: code, expiring: TOTP.remainingSeconds(period: period, date: now) <= 10, size: 17)
                                CountdownRing(period: period, date: now, size: 20)
                                    .opacity(code == nil ? 0.3 : 1)
                            }
                        }
                    }
                } header: {
                    Text("TOTP-Secret")
                } footer: {
                    if let secretError {
                        Text(secretError).foregroundStyle(.red)
                    }
                }

                Section {
                    TextField("Fenstertitel-Match", text: $match, prompt: Text("z. B. Viscosity"))
                } header: {
                    Text("Auto-Fill")
                } footer: {
                    Text("Wird bei \(HotkeyService.displayText) mit dem Titel des aktiven Fensters verglichen. Gross-/Kleinschreibung und Satzzeichen spielen keine Rolle; ohne Match gelten Name und Aussteller.")
                }

                Section {
                    DisclosureGroup("Erweitert", isExpanded: $showAdvanced) {
                        Picker("Stellen", selection: $digits) {
                            ForEach([6, 7, 8], id: \.self) { Text("\($0)").tag($0) }
                        }
                        Picker("Gültigkeit", selection: $period) {
                            Text("30 Sekunden").tag(30)
                            Text("60 Sekunden").tag(60)
                            if ![30, 60].contains(period) {
                                Text("\(period) Sekunden").tag(period)
                            }
                        }
                        Picker("Algorithmus", selection: $algorithm) {
                            ForEach(["SHA1", "SHA256", "SHA512"], id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .onChange(of: issuer) { oldValue, newValue in
                if match.isEmpty || match == oldValue {
                    match = newValue
                }
            }

            Divider()
            HStack {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(14)
        }
        .frame(width: 480, height: 640)
    }

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.title = "Logo wählen"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        guard let image = NSImage(contentsOf: url), image.isValid else {
            errorMessage = "Das Bild konnte nicht gelesen werden."
            return
        }
        newLogo = image
        clearLogo = false
        errorMessage = nil
    }

    private func save() {
        var account = existing?.model ?? TotpAccount()
        account.name = name.trimmingCharacters(in: .whitespaces)
        account.accountLogin = login.trimmingCharacters(in: .whitespaces)
        account.issuer = issuer.trimmingCharacters(in: .whitespaces)
        account.windowTitleMatch = match.trimmingCharacters(in: .whitespaces)
        account.digits = digits
        account.period = period
        account.algorithm = algorithm
        do {
            try model.upsert(account, secret: secret, newLogo: newLogo, clearLogo: clearLogo)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
