import AppKit
import AutototpCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var model: AppModel!
    private let hotkey = HotkeyService()
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var panel: FloatingPanel?
    private var menuTimer: Timer?
    private var menuCodeItems: [(NSMenuItem, UUID)] = []

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = AccountStore()
        do {
            model = try AppModel(store: store, box: try store.makeSecretBox())
        } catch {
            NSApp.activate()
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Autototp kann die Accounts nicht laden"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        NSApp.mainMenu = buildMainMenu()
        setUpStatusItem()

        hotkey.onPress = { [weak self] in
            self?.handleHotkey()
        }
        model.hotkeyRegistered = hotkey.register()

        if !model.settings.startMinimized {
            showMainWindow()
        }
        if !AXIsProcessTrusted() {
            Permissions.requestAccessibility()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey.unregister()
    }

    // MARK: Windows

    @objc func showMainWindow() {
        if mainWindow == nil {
            let hosting = NSHostingController(rootView: MainView(model: model, openSettings: { [weak self] in
                self?.showSettings()
            }))
            hosting.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.title = "Autototp"
            window.setContentSize(NSSize(width: 500, height: 580))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("AutototpMainWindow")
            mainWindow = window
        }
        bringToFront(mainWindow!)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable]
            window.title = "Einstellungen"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        bringToFront(settingsWindow!)
    }

    @objc func showAddAccount() {
        showMainWindow()
        model.sheet = .add
    }

    @objc func showImport() {
        showMainWindow()
        model.sheet = .importAccounts
    }

    private func bringToFront(_ window: NSWindow) {
        // Dock icon and ⌘-Tab only while a regular window is open; menu-bar-only otherwise.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let anyVisible = [self.mainWindow, self.settingsWindow].contains { $0?.isVisible == true }
            if !anyVisible {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    // MARK: Hotkey flow

    @objc func handleHotkey() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        guard !model.items.isEmpty else {
            showMainWindow()
            return
        }
        guard AXIsProcessTrusted() else {
            askForAccessibility()
            return
        }

        let context = ForegroundContext.capture()
        var matches = context.isOwnApp ? [] : WindowMatcher.findMatches(model.accounts, windowTitle: context.windowTitle)
        if matches.isEmpty && !context.isOwnApp {
            matches = WindowMatcher.findMatches(model.accounts, windowTitle: context.appName)
        }
        let usable = matches.compactMap { match -> (AccountMatch, AccountItem)? in
            guard let item = model.item(match.account.id), item.secret != nil else { return nil }
            return (match, item)
        }

        if usable.count == 1 {
            showConfirm(usable[0].1, match: usable[0].0, context: context)
        } else {
            showPicker(preferred: Set(usable.map(\.1.id)), context: context)
        }
    }

    private func showConfirm(_ item: AccountItem, match: AccountMatch, context: ForegroundContext) {
        let view = ConfirmFillView(
            item: item,
            matchLabel: match.label,
            targetTitle: context.isOwnApp ? "" : context.displayTitle,
            sendEnter: model.settings.sendEnterAfterCode,
            onConfirm: { [weak self] in self?.fill(item, context: context) },
            onChooseOther: { [weak self] in
                self?.closePanel()
                self?.showPicker(preferred: [item.id], context: context)
            },
            onCancel: { [weak self] in self?.closePanel() }
        )
        present(FloatingPanel(content: view, onCancel: { [weak self] in self?.closePanel() }))
    }

    private func showPicker(preferred: Set<UUID>, context: ForegroundContext) {
        let view = QuickPickerView(
            items: model.items.filter { $0.secret != nil },
            preferredIDs: preferred,
            targetTitle: context.isOwnApp ? "" : context.displayTitle,
            onPick: { [weak self] item in self?.fill(item, context: context) },
            onCopy: { [weak self] item in
                self?.model.copyCode(item)
                self?.closePanel()
            },
            onCancel: { [weak self] in self?.closePanel() }
        )
        present(FloatingPanel(content: view, onCancel: { [weak self] in self?.closePanel() }))
    }

    private func present(_ newPanel: FloatingPanel) {
        panel = newPanel
        newPanel.positionOnActiveScreen()
        newPanel.makeKeyAndOrderFront(nil)
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func fill(_ item: AccountItem, context: ForegroundContext) {
        closePanel()
        let pressReturn = model.settings.sendEnterAfterCode
        context.restore { [weak self] in
            // Compute at typing time so the code is never from the previous period.
            guard let code = self?.model.item(item.id)?.code() else { return }
            KeyTyper.type(code, pressReturn: pressReturn)
        }
    }

    private func askForAccessibility() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Autototp braucht Zugriff auf die Bedienungshilfen"
        alert.informativeText = "Nur so kann Autototp das aktive Fenster erkennen und den Code eintippen. Erlaube Autototp unter Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen und drücke \(HotkeyService.displayText) erneut."
        alert.addButton(withTitle: "Systemeinstellungen öffnen")
        alert.addButton(withTitle: "Abbrechen")
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.requestAccessibility()
            Permissions.openAccessibilitySettings()
        }
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusIcon.make()
        statusItem.button?.toolTip = "Autototp"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        menu.removeAllItems()
        menuCodeItems = []

        if model.items.isEmpty {
            menu.addItem(disabled("Noch keine Accounts"))
        } else {
            menu.addItem(NSMenuItem.sectionHeader(title: "Klicken kopiert den Code"))
            for item in model.items.prefix(25) {
                let entry = NSMenuItem(title: item.name, action: #selector(copyFromMenu(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = item.id
                if !item.login.isEmpty {
                    entry.subtitle = item.login
                }
                entry.image = menuIcon(for: item)
                entry.badge = NSMenuItemBadge(string: item.code().map(TOTP.format) ?? "–")
                menu.addItem(entry)
                menuCodeItems.append((entry, item.id))
            }
        }

        menu.addItem(.separator())
        let fillItem = NSMenuItem(title: "Code einfügen …", action: #selector(handleHotkey), keyEquivalent: "t")
        fillItem.keyEquivalentModifierMask = [.control, .option]
        fillItem.target = self
        menu.addItem(fillItem)
        menu.addItem(item("Autototp öffnen", #selector(showMainWindow)))
        menu.addItem(item("Einstellungen …", #selector(showSettings), key: ","))
        menu.addItem(.separator())
        let loginItem = item("Bei der Anmeldung öffnen", #selector(toggleLoginItem))
        loginItem.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(item("Autototp beenden", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshMenuCodes() }
        }
        RunLoop.main.add(timer, forMode: .common)
        menuTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        menuTimer?.invalidate()
        menuTimer = nil
    }

    private func refreshMenuCodes() {
        for (entry, id) in menuCodeItems {
            entry.badge = NSMenuItemBadge(string: model.item(id)?.code().map(TOTP.format) ?? "–")
        }
    }

    @objc private func toggleLoginItem() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Autostart konnte nicht geändert werden"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func copyFromMenu(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID, let item = model.item(id) {
            model.copyCode(item)
        }
    }

    private func menuIcon(for item: AccountItem) -> NSImage? {
        let renderer = ImageRenderer(content: LogoTile(name: item.name, image: item.logo, size: 18))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = target ?? self
        return entry
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    // MARK: Main menu

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Über Autototp", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(item("Einstellungen …", #selector(showSettings), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Autototp ausblenden", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: "Andere ausblenden", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Autototp beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, title: "Autototp", to: main)

        let fileMenu = NSMenu(title: "Ablage")
        fileMenu.addItem(item("Account hinzufügen …", #selector(showAddAccount), key: "n"))
        fileMenu.addItem(item("Importieren …", #selector(showImport), key: "i"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Fenster schliessen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(fileMenu, title: "Ablage", to: main)

        let editMenu = NSMenu(title: "Bearbeiten")
        editMenu.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(editMenu, title: "Bearbeiten", to: main)

        let windowMenu = NSMenu(title: "Fenster")
        windowMenu.addItem(withTitle: "Im Dock ablegen", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        addSubmenu(windowMenu, title: "Fenster", to: main)
        NSApp.windowsMenu = windowMenu

        return main
    }

    private func addSubmenu(_ submenu: NSMenu, title: String, to main: NSMenu) {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = submenu
        main.addItem(holder)
    }
}

// MARK: - Floating panel

/// Non-activating panel: takes keyboard focus without deactivating the app the code is meant for.
final class FloatingPanel: NSPanel {
    private let onCancel: () -> Void

    init<Content: View>(content: Content, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let hosting = NSHostingView(rootView: content
            .background(VisualEffectBackground(material: .popover))
            .clipShape(shape)
            .overlay(shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)))
        contentView = hosting
        setContentSize(hosting.fittingSize)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }

    /// Horizontally centred, in the upper third of the screen under the mouse – where Spotlight appears.
    func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            center()
            return
        }
        let size = frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - visible.height * 0.28 - size.height / 2
        )
        setFrameOrigin(origin)
    }
}

// MARK: - Menu bar icon

/// Template version of the app icon: a solid keycap with the countdown ring and keyhole cut out.
/// Drawn as vectors so it stays crisp at any scale and follows the menu bar's light/dark tint.
enum StatusIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width / 18
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0.75 * s, y: 0.75 * s, width: 16.5 * s, height: 16.5 * s),
                         xRadius: 4.3 * s, yRadius: 4.3 * s).fill()

            guard let context = NSGraphicsContext.current else { return true }
            context.compositingOperation = .destinationOut
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Three-quarter countdown ring, starting at 12 o'clock.
            let center = NSPoint(x: 9 * s, y: 9 * s)
            let ring = NSBezierPath()
            ring.appendArc(withCenter: center, radius: 5.1 * s, startAngle: 90, endAngle: 180, clockwise: true)
            ring.lineWidth = 1.9 * s
            ring.lineCapStyle = .round
            ring.stroke()

            // Keyhole.
            NSBezierPath(ovalIn: NSRect(x: 7.3 * s, y: 8.6 * s, width: 3.4 * s, height: 3.4 * s)).fill()
            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: 8.15 * s, y: 9.2 * s))
            stem.line(to: NSPoint(x: 9.85 * s, y: 9.2 * s))
            stem.line(to: NSPoint(x: 10.45 * s, y: 5.9 * s))
            stem.line(to: NSPoint(x: 7.55 * s, y: 5.9 * s))
            stem.close()
            stem.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Autototp"
        return image
    }
}
