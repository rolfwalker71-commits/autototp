import AppKit
import AutototpCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Allgemein") {
                Toggle("Bei der Anmeldung öffnen", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Beim Start nur in der Menüleiste", isOn: Binding(
                    get: { model.settings.startMinimized },
                    set: { value in model.updateSettings { $0.startMinimized = value } }
                ))
            }

            Section {
                Picker("Zeilenhöhe", selection: Binding(
                    get: { model.settings.density },
                    set: { value in model.updateSettings { $0.density = value } }
                )) {
                    ForEach(RowDensity.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Bewegter Hintergrund", isOn: Binding(
                    get: { model.settings.animatedBackground },
                    set: { value in model.updateSettings { $0.animatedBackground = value } }
                ))
                Toggle("Logos automatisch laden", isOn: Binding(
                    get: { model.settings.fetchLogos },
                    set: { value in model.updateSettings { $0.fetchLogos = value } }
                ))
            } header: {
                Text("Darstellung")
            } footer: {
                Text("Beim Laden der Logos wird der Domainname des Ausstellers an einen Icon-Dienst gesendet. Einzelne Logos holst du im Account-Editor mit „Logo holen“.")
            }

            Section {
                LabeledContent("Kurzbefehl") {
                    HStack(spacing: 8) {
                        if model.hotkeyRegistered {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        KeyCap(text: HotkeyService.displayText)
                    }
                }
                Toggle("Nach dem Code Return drücken", isOn: Binding(
                    get: { model.settings.sendEnterAfterCode },
                    set: { value in model.updateSettings { $0.sendEnterAfterCode = value } }
                ))
                LabeledContent(Permissions.accessibilityPaneName) {
                    if model.accessibilityTrusted {
                        Label("Erlaubt", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Zugriff erlauben …") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
            } header: {
                Text("Auto-Fill")
            } footer: {
                Text("\(HotkeyService.displayText) sucht den Account zum aktiven Fenster und tippt den Code ein. Dafür muss Autototp unter \(Permissions.accessibilityPanePath) eingeschaltet sein.")
            }

            Section("Sicherheit") {
                Label {
                    Text("Secrets werden mit AES-256-GCM verschlüsselt gespeichert. Der Schlüssel liegt in deinem macOS-Schlüsselbund und ist nur mit deinem Benutzer auf diesem Mac lesbar.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.tint)
                }
            }

            Section {
                LabeledContent {
                    Button("Tokens exportieren …") {
                        Exporter.run(model: model)
                    }
                } label: {
                    Text("Export")
                    Text("Alle Accounts als otpauth://-Links – lesbar für Autototp, 2FAS, Aegis und andere. Die Datei enthält die Secrets im Klartext.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent {
                    Button("Im Finder zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.store.fileURL])
                    }
                } label: {
                    Text("Speicherort")
                    Text((model.store.fileURL.path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Daten")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 620)
        .onAppear {
            // May have been toggled from the menu bar since the window was created.
            launchAtLogin = LoginItem.isEnabled
        }
    }
}
