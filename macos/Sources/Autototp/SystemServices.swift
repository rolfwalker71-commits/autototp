import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Global hotkey (Carbon; needs no extra permission)

final class HotkeyService {
    static let displayText = "⌃⌥T"

    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Registers Control + Option + T, the same chord as Ctrl + Alt + T on Windows.
    func register() -> Bool {
        unregister()

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else {
                return noErr
            }
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                service.onPress?()
            }
            return noErr
        }, 1, &spec, selfPointer, &handlerRef)
        guard installStatus == noErr else {
            return false
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4154_4F54), id: 1) // "ATOT"
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        hotKeyRef = nil
        handlerRef = nil
    }
}

// MARK: - Foreground window (Accessibility API)

struct ForegroundContext {
    let app: NSRunningApplication?
    let window: AXUIElement?
    let windowTitle: String

    var appName: String { app?.localizedName ?? "" }
    var isOwnApp: Bool { app?.processIdentifier == ProcessInfo.processInfo.processIdentifier }

    /// "Titel – App" for display in the confirm panel.
    var displayTitle: String {
        switch (windowTitle.isEmpty, appName.isEmpty) {
        case (false, false): return "\(windowTitle) – \(appName)"
        case (false, true): return windowTitle
        case (true, false): return appName
        case (true, true): return ""
        }
    }

    static func capture() -> ForegroundContext {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return ForegroundContext(app: nil, window: nil, windowTitle: "")
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let windowValue,
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
            return ForegroundContext(app: app, window: nil, windowTitle: "")
        }
        let window = windowValue as! AXUIElement
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
        let title = (titleValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ForegroundContext(app: app, window: window, windowTitle: title)
    }

    /// Brings the captured app and window back to the front, then calls `completion`
    /// once it is frontmost (or after a short timeout).
    func restore(then completion: @escaping () -> Void) {
        guard let app, !app.isTerminated else {
            completion()
            return
        }
        if let window {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        app.activate()

        let deadline = Date().addingTimeInterval(1.0)
        func poll() {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier || Date() > deadline {
                // Give the target a moment to restore keyboard focus inside its window.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: completion)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: poll)
            }
        }
        poll()
    }
}

// MARK: - Typing (CGEvent; needs Accessibility permission)

enum KeyTyper {
    private static let digitKeyCodes: [Character: CGKeyCode] = [
        "0": CGKeyCode(kVK_ANSI_0), "1": CGKeyCode(kVK_ANSI_1), "2": CGKeyCode(kVK_ANSI_2),
        "3": CGKeyCode(kVK_ANSI_3), "4": CGKeyCode(kVK_ANSI_4), "5": CGKeyCode(kVK_ANSI_5),
        "6": CGKeyCode(kVK_ANSI_6), "7": CGKeyCode(kVK_ANSI_7), "8": CGKeyCode(kVK_ANSI_8),
        "9": CGKeyCode(kVK_ANSI_9),
    ]

    /// Types the digits (key code plus Unicode string, so any keyboard layout works) and optionally Return.
    static func type(_ text: String, pressReturn: Bool) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for ch in text {
            post(keyCode: digitKeyCodes[ch] ?? 0, unicode: String(ch), source: source)
        }
        if pressReturn {
            post(keyCode: CGKeyCode(kVK_Return), unicode: nil, source: source)
        }
    }

    private static func post(keyCode: CGKeyCode, unicode: String?, source: CGEventSource?) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else {
                continue
            }
            event.flags = []
            if let unicode {
                let chars = Array(unicode.utf16)
                event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
            }
            event.post(tap: .cghidEventTap)
            usleep(6_000)
        }
    }
}

// MARK: - Accessibility + login item

enum Permissions {
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
