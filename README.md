# Autototp

Native Windows system-tray app (C# WPF, .NET 8) for managing TOTP accounts and typing the current code into the active window.

## Features

- Account list with live 6-digit codes and a 30-second progress bar ([Otp.NET](https://www.nuget.org/packages/Otp.NET))
- Search by name, issuer, or window-title match
- Close-to-tray (the X hides the window; the app stays in the notification area)
- Tray menu: Open, enable/disable autostart, Exit
- Autostart via `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
- Secrets stored in `%AppData%\TOTPManager\accounts.json`, encrypted with Windows DPAPI (`ProtectedData`, current user)
- Data model ready for an optional master password (disabled by default)
- Manual add, `.2fas` import (including password-protected backups), and `otpauth://` URIs
- Global hotkey `Ctrl + Alt + T`: match the foreground window title, type the code, then `{ENTER}`
- Quick picker at the cursor when the match is missing or ambiguous

## Build (Windows)

```bash
dotnet publish src/Autototp/Autototp.csproj -c Release -r win-x86 --self-contained true -p:PublishSingleFile=true -o publish/win-x86
dotnet publish src/Autototp/Autototp.csproj -c Release -r win-arm64 --self-contained true -p:PublishSingleFile=true -o publish/win-arm64
```

The WPF project targets `net8.0-windows` and must be built on Windows. CI publishes **win-x86** and **win-arm64** only.

## Usage

1. Start `Autototp.exe`.
2. Add an account (name, Base32 secret, optional window-title match such as `Stooss` or `Viscosity`) or import a 2FAS backup.
3. Focus a login/OTP field and press `Ctrl + Alt + T`.
4. Closing the window keeps the tray icon; use **Beenden** to quit.

## Security

- TOTP secrets are never stored as plaintext in `accounts.json`.
- DPAPI binds ciphertext to the current Windows user. Copying the file to another account will not decrypt the secrets.
- The optional master-password fields (`kdf`, `iterations`, `salt`, `verifier`) are reserved for a later AES layer.

## CI / GHCR

Every push to `main` runs [`.github/workflows/build.yml`](.github/workflows/build.yml):

1. Publishes self-contained single-file builds for `win-x86` and `win-arm64` on `windows-latest` and uploads them as artifacts.
2. Packages both binaries into `ghcr.io/rolfwalker71-commits/autototp` (distribution image; the UI itself is Windows-only).

Remote Compose uses only the GHCR image (no local `build:`):

```bash
docker compose pull && docker compose up
```

Local image build:

```bash
docker compose -f docker-compose.yml -f docker-compose.build.yml build
```
