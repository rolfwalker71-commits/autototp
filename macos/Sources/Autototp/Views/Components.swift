import AppKit
import AutototpCore
import SwiftUI

/// Account logo, or a coloured letter tile like Contacts/Passwords use when there is none.
struct LogoTile: View {
    let name: String
    let image: NSImage?
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.1)
                    .frame(width: size, height: size)
                    .background(.white, in: shape)
            } else {
                Text(initial)
                    .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(
                        LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom),
                        in: shape
                    )
            }
        }
        .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    private var color: Color {
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .teal, .green, .cyan, .brown]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return palette[hash % palette.count]
    }
}

/// Circular countdown like the verification codes in the Passwords app.
struct CountdownRing: View {
    let period: Int
    let date: Date
    var size: CGFloat = 22

    var body: some View {
        let progress = TOTP.progress(period: period, date: date)
        let seconds = TOTP.remainingSeconds(period: period, date: date)
        let tint: Color = seconds <= 10 ? .red : .accentColor
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: size * 0.12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(seconds)")
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(seconds <= 10 ? .red : .secondary)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Noch \(seconds) Sekunden gültig")
    }
}

struct CodeText: View {
    let code: String?
    let expiring: Bool
    var size: CGFloat = 20

    var body: some View {
        Text(code.map(TOTP.format) ?? "––– –––")
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(code == nil ? AnyShapeStyle(.tertiary) : expiring ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            .contentTransition(.numericText())
    }
}

/// Keycap-style shortcut hint, e.g. [⌃⌥T].
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.tertiary.opacity(0.5), lineWidth: 0.5))
    }
}

/// Behind-window blur for the floating panels.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
