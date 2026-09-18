import AppKit
import AutototpCore
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    enum Source: Hashable {
        case twoFas
        case otpauth
    }

    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State var source: Source = .twoFas
    @State var fileName: String?
    @State private var fileData: Data?
    @State var needsPassword = false
    @State private var password = ""
    @State private var uriText = ""
    @State var rows: [ImportedAccount] = []
    @State var warnings: [String] = []
    @State private var errorMessage: String?

    init(model: AppModel) {
        self.model = model
    }

    /// Preview state for screenshots.
    init(model: AppModel, previewFile: String, rows: [ImportedAccount], warnings: [String]) {
        self.model = model
        _fileName = State(initialValue: previewFile)
        _rows = State(initialValue: rows)
        _warnings = State(initialValue: warnings)
    }

    private var selectedCount: Int {
        rows.filter(\.isSelected).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Quelle", selection: $source) {
                Text("2FAS-Backup").tag(Source.twoFas)
                Text("otpauth://-Links").tag(Source.otpauth)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .frame(maxWidth: .infinity)

            Group {
                switch source {
                case .twoFas:
                    twoFasInput
                case .otpauth:
                    otpauthInput
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            previewTable

            if !warnings.isEmpty {
                DisclosureGroup(warnings.count == 1 ? "1 Eintrag übersprungen" : "\(warnings.count) Einträge übersprungen") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(warnings, id: \.self) { Text($0) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
            }

            HStack {
                Text("Logos kannst du nach dem Import pro Account setzen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(selectedCount == 1 ? "1 Account importieren" : "\(selectedCount) Accounts importieren", action: importSelected)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedCount == 0)
            }
        }
        .padding(20)
        .frame(width: 640, height: 560)
        .onChange(of: source) {
            errorMessage = nil
        }
    }

    private var twoFasInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button("Backup-Datei wählen …", action: chooseFile)
                if let fileName {
                    Label(fileName, systemImage: "doc")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("In 2FAS: Einstellungen → Backup → Exportieren (.2fas)")
                        .foregroundStyle(.secondary)
                }
            }
            if needsPassword {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                    SecureField("Backup-Passwort", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .onSubmit(parseFile)
                    Button("Entschlüsseln", action: parseFile)
                        .disabled(password.isEmpty)
                }
            }
        }
    }

    private var otpauthInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $uriText)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                .frame(height: 90)
                .overlay(alignment: .topLeading) {
                    if uriText.isEmpty {
                        Text("otpauth://totp/GitHub:rolf?secret=…&issuer=GitHub\n(ein Link pro Zeile)")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }
            Button("Links auswerten") {
                apply(ImportService.parseOtpAuthText(uriText))
            }
            .disabled(uriText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var previewTable: some View {
        Table(rows) {
            TableColumn("") { row in
                Toggle("", isOn: binding(row.id, \.isSelected))
                    .labelsHidden()
            }
            .width(22)

            TableColumn("Account") { row in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(row.name).lineLimit(1)
                        if row.isDuplicate {
                            Text("vorhanden")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .background(.quaternary, in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !row.accountLogin.isEmpty {
                        Text(row.accountLogin)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            TableColumn("Aussteller") { row in
                Text(row.issuer).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 80, ideal: 110)

            TableColumn("Fenstertitel-Match") { row in
                TextField("Match", text: binding(row.id, \.windowTitleMatch))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }
            .width(min: 110, ideal: 150)
        }
        .overlay {
            if rows.isEmpty {
                Text(source == .twoFas ? "Wähle eine 2FAS-Backup-Datei." : "Füge otpauth://-Links ein.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<ImportedAccount, Value>) -> Binding<Value> {
        Binding {
            rows.first { $0.id == id }![keyPath: keyPath]
        } set: { value in
            if let index = rows.firstIndex(where: { $0.id == id }) {
                rows[index][keyPath: keyPath] = value
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "2FAS-Backup wählen"
        panel.allowedContentTypes = [UTType(filenameExtension: "2fas") ?? .json, .json]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            fileData = try Data(contentsOf: url)
            fileName = url.lastPathComponent
            password = ""
            needsPassword = ImportService.is2FasEncrypted(fileData!)
            rows = []
            warnings = []
            errorMessage = nil
            if !needsPassword {
                parseFile()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parseFile() {
        guard let fileData else {
            return
        }
        do {
            apply(try ImportService.parse2FasJSON(fileData, password: password))
        } catch {
            rows = []
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ result: ImportResult) {
        rows = result.accounts.map { account in
            var account = account
            account.isDuplicate = model.isKnownSecret(account.secret)
            account.isSelected = !account.isDuplicate
            return account
        }
        warnings = result.warnings
        errorMessage = rows.isEmpty && warnings.isEmpty ? "Keine Accounts gefunden." : nil
    }

    private func importSelected() {
        do {
            try model.importAccounts(rows)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
