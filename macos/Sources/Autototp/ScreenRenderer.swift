import AppKit
import AutototpCore
import SwiftUI

/// `Autototp --render-screens <dir>` writes PNGs of every window with sample data (light + dark),
/// for docs and design review. Uses no stored data and no Keychain.
@MainActor
final class ScreenRenderer: NSObject, NSApplicationDelegate {
    private let outputDirectory: URL
    private var windows: [NSWindow] = []

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        // 12 s into a 30 s period so rings are partly filled; one account shows the red last-10-seconds state.
        let date = Date(timeIntervalSince1970: 1_790_000_052)
        let items = Self.sampleItems()
        let model = AppModel(preview: items)
        let matchItem = items[1]
        let imported = Self.sampleImport()

        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let look = NSAppearance(named: appearance)
            render(
                "1-hauptfenster-\(suffix)",
                MainView(model: model, frozenDate: date),
                size: NSSize(width: 500, height: 520),
                appearance: look,
                toolbar: true
            )
            render(
                "2-account-bearbeiten-\(suffix)",
                AccountEditorView(model: model, existing: matchItem, frozenDate: date),
                appearance: look
            )
            render(
                "3-import-\(suffix)",
                ImportView(model: model, previewFile: "2fas-backup-2026-09-18.2fas", rows: imported, warnings: ["Übersprungen (STEAM): Steam"]),
                appearance: look
            )
            render("4-einstellungen-\(suffix)", SettingsView(model: model), appearance: look, title: "Einstellungen")
            renderPanel(
                "5-schnellauswahl-\(suffix)",
                QuickPickerView(
                    items: items,
                    preferredIDs: [items[1].id, items[4].id],
                    targetTitle: "Stooss Remote Access – Safari",
                    frozenDate: date
                ),
                appearance: look
            )
            renderPanel(
                "6-bestaetigen-\(suffix)",
                ConfirmFillView(
                    item: matchItem,
                    matchLabel: "Match: Viscosity",
                    targetTitle: "Viscosity – Verbindung „Büro“",
                    sendEnter: true,
                    frozenDate: date
                ),
                appearance: look
            )
        }

        writeStatusIconPreview()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for (window, name) in self.pending {
                self.capture(window, name: name)
            }
            print("Screens geschrieben nach \(self.outputDirectory.path)")
            NSApp.terminate(nil)
        }
    }

    private var pending: [(NSWindow, String)] = []

    private func render<V: View>(_ name: String, _ view: V, size: NSSize? = nil, appearance: NSAppearance?, toolbar: Bool = false, title: String = "Autototp") {
        let hosting = NSHostingController(rootView: view)
        if toolbar {
            hosting.sceneBridgingOptions = [.toolbars, .title]
        }
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.title = title
        window.appearance = appearance
        if let size {
            window.setContentSize(size)
        }
        show(window, name: name)
    }

    private func renderPanel<V: View>(_ name: String, _ view: V, appearance: NSAppearance?) {
        let panel = FloatingPanel(content: view, onCancel: {})
        panel.appearance = appearance
        show(panel, name: name)
    }

    private func show(_ window: NSWindow, name: String) {
        // Placed far off-screen so nothing flashes on the user's desktop.
        window.setFrameOrigin(NSPoint(x: -20_000 - CGFloat(windows.count) * 1_000, y: -20_000))
        window.orderFrontRegardless()
        windows.append(window)
        pending.append((window, name))
    }

    private func capture(_ window: NSWindow, name: String) {
        guard let frameView = window is FloatingPanel ? window.contentView : window.contentView?.superview else {
            return
        }
        frameView.layoutSubtreeIfNeeded()
        let bounds = frameView.bounds
        // 2x so the PNGs look sharp on Retina displays.
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * 2),
            pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return
        }
        rep.size = bounds.size
        frameView.cacheDisplay(in: bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        }
    }

    /// Menu bar strip with the template icon next to system-like glyphs, light and dark, at 4x.
    private func writeStatusIconPreview() {
        let scale: CGFloat = 4
        let strip = NSSize(width: 150, height: 24)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(strip.width * scale), pixelsHigh: Int(strip.height * 2 * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = NSSize(width: strip.width, height: strip.height * 2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let icon = StatusIcon.make()
        let neighbours = ["wifi", "battery.75percent", "magnifyingglass"].compactMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        }
        for (row, (background, tint)) in [(NSColor(white: 0.93, alpha: 1), NSColor.black), (NSColor(white: 0.16, alpha: 1), NSColor.white)].enumerated() {
            let y = CGFloat(1 - row) * strip.height
            background.setFill()
            NSRect(x: 0, y: y, width: strip.width, height: strip.height).fill()
            var x: CGFloat = 12
            for glyph in [icon] + neighbours {
                let tinted = NSImage(size: glyph.size, flipped: false) { rect in
                    glyph.draw(in: rect)
                    tint.set()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: NSRect(x: x, y: y + (strip.height - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height))
                x += glyph.size.width + 16
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: outputDirectory.appendingPathComponent("7-menueleiste.png"))
    }

    // MARK: Sample data

    private static func account(_ name: String, login: String, issuer: String, match: String, secret: String, period: Int = 30) -> AccountItem {
        var model = TotpAccount()
        model.name = name
        model.accountLogin = login
        model.issuer = issuer
        model.windowTitleMatch = match
        model.period = period
        return AccountItem(model: model, secret: secret, logo: nil)
    }

    static func sampleItems() -> [AccountItem] {
        [
            account("GitHub", login: "rolf@example.ch", issuer: "GitHub", match: "GitHub", secret: "JBSWY3DPEHPK3PXP"),
            account("Stooss VPN", login: "rwalker", issuer: "Viscosity", match: "Viscosity", secret: "KRSXG5CTMVRXEZLU"),
            account("Microsoft 365", login: "rolf@firma.ch", issuer: "Microsoft", match: "Office", secret: "GEZDGNBVGY3TQOJQ"),
            account("AWS Konsole", login: "admin", issuer: "Amazon Web Services", match: "", secret: "MFRGGZDFMZTWQ2LK", period: 20),
            account("Stooss Remote", login: "", issuer: "Stooss", match: "Stooss Remote", secret: "NBSWY3DPFQQHO33S"),
        ]
    }

    static func sampleImport() -> [ImportedAccount] {
        func row(_ name: String, _ login: String, _ issuer: String, duplicate: Bool = false) -> ImportedAccount {
            var account = ImportedAccount()
            account.name = name
            account.accountLogin = login
            account.issuer = issuer
            account.windowTitleMatch = issuer
            account.isDuplicate = duplicate
            account.isSelected = !duplicate
            return account
        }
        return [
            row("GitHub", "rolf@example.ch", "GitHub", duplicate: true),
            row("Google", "rolf@gmail.com", "Google"),
            row("Dropbox", "rolf@example.ch", "Dropbox"),
            row("Cloudflare", "ops@firma.ch", "Cloudflare"),
            row("Proton", "rolf@proton.me", "Proton"),
        ]
    }
}
