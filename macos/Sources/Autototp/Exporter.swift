import AppKit
import AutototpCore

/// Saves all accounts as otpauth:// URIs. The file holds the secrets in plain text,
/// so the user has to confirm first and the file is written with owner-only permissions.
@MainActor
enum Exporter {
    static func run(model: AppModel) {
        let entries = model.items.compactMap { item in
            item.secret.map { ExportService.Entry(account: item.model, secret: $0) }
        }
        guard !entries.isEmpty else {
            alert("Nichts zu exportieren", "Es sind keine Accounts gespeichert.")
            return
        }

        let warning = NSAlert()
        warning.alertStyle = .warning
        warning.messageText = "\(entries.count) Accounts im Klartext exportieren?"
        warning.informativeText = """
        Die Datei enthält alle TOTP-Secrets unverschlüsselt. Wer sie liest, kann deine Codes erzeugen.
        Bewahre sie nur verschlüsselt auf und lösche sie nach dem Import.

        Einlesen lässt sie sich in Autototp unter „Importieren …“ mit otpauth://-Links sowie in 2FAS, Aegis und anderen Authenticator-Apps.
        """
        warning.addButton(withTitle: "Exportieren …")
        warning.addButton(withTitle: "Abbrechen")
        guard warning.runModal() == .alertFirstButtonReturn else {
            return
        }

        let panel = NSSavePanel()
        panel.title = "Tokens exportieren"
        panel.nameFieldStringValue = ExportService.suggestedFileName()
        panel.allowedContentTypes = [.plainText]
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let text = ExportService.file(for: entries)
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            alert("Export fehlgeschlagen", error.localizedDescription)
        }
    }

    private static func alert(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
