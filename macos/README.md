# Autototp für macOS

Native Menüleisten-App (SwiftUI/AppKit) mit denselben Funktionen wie die Windows-Version.

- Account-Liste mit Live-Codes und Countdown-Ring, Suche in der Toolbar
- Menüleisten-Menü mit allen Codes (Klick kopiert)
- Globaler Kurzbefehl **⌃⌥T**: erkennt das aktive Fenster, bestätigt den passenden Account oder zeigt eine Spotlight-artige Schnellauswahl und tippt den Code (optional mit Return) ein
- Import von 2FAS-Backups (auch passwortgeschützt) und `otpauth://`-Links; bereits vorhandene Secrets werden erkannt
- Logos pro Account, Autostart über Anmeldeobjekte, Fenster schliessen = App bleibt in der Menüleiste

## Bauen

Es reichen die Command Line Tools (kein Xcode):

```bash
scripts/build-app.sh             # → build/Autototp.app
scripts/build-app.sh --install   # zusätzlich nach /Applications kopieren
scripts/test.sh                  # Kern-Tests (TOTP RFC 6238, Matching, Import, Speicher)
```

Die Skripte rufen `swiftc` direkt auf. Das macOS-27-SDK braucht für SwiftUI ein Makro-Plugin, das nur mit Xcode kommt; ohne Xcode nimmt `build-app.sh` automatisch das neueste installierte SDK 26 (überschreibbar mit `AUTOTOTP_SDK`). `Package.swift` funktioniert mit Xcode oder mit `SDKROOT=…/MacOSX26.5.sdk swift build`.

Das App-Icon ist `Resources/AppIcon.svg`; das Build-Skript rendert es mit Quick Look in alle Grössen.

Screenshots aller Fenster mit Beispieldaten:

```bash
build/Autototp.app/Contents/MacOS/Autototp --render-screens /tmp/autototp-screens
```

## Berechtigungen

Für ⌃⌥T braucht die App **Bedienungshilfen** (Systemeinstellungen → Datenschutz & Sicherheit). Damit liest sie den Titel des aktiven Fensters und tippt den Code ein.

Die Freigabe hängt an der Code-Signatur. Bei ad-hoc-signierten Builds muss sie nach jedem Neubau erneut erteilt werden. Mit einer festen Signatur bleibt sie erhalten:

```bash
AUTOTOTP_SIGN_IDENTITY="Apple Development: …" scripts/build-app.sh --install
```

## Daten und Sicherheit

- `~/Library/Application Support/Autototp/accounts.json` (+ `logos/`), Dateirechte 0600
- Secrets sind mit AES-256-GCM verschlüsselt. Der Schlüssel liegt im Anmelde-Schlüsselbund (Eintrag „Autototp“), analog zu DPAPI unter Windows.
- Das Dateiformat entspricht dem der Windows-App. Die Secrets sind aber anders verschlüsselt, deshalb lassen sich `accounts.json`-Dateien nicht zwischen den Plattformen austauschen. Zum Übertragen einfach das 2FAS-Backup auf beiden Systemen importieren.
- `AUTOTOTP_DATA_DIR=/pfad` nutzt einen separaten Datenordner mit Schlüsseldatei statt Schlüsselbund (nur für Entwicklung und Tests).
