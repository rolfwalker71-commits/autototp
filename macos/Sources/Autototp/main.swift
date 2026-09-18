import AppKit

let app = NSApplication.shared
let arguments = CommandLine.arguments

if let index = arguments.firstIndex(of: "--render-screens"), index + 1 < arguments.count {
    let output = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    let renderer = MainActor.assumeIsolated { ScreenRenderer(outputDirectory: output) }
    app.delegate = renderer
    app.run()
} else {
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
