import AppKit
import AutototpCore
import SwiftUI

/// Account logo, or a coloured letter tile in the account's own colour.
struct LogoTile: View {
    let name: String
    let image: NSImage?
    var size: CGFloat = 36
    var colorIndex: Int?

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
                    .font(Theme.codeFont(size: size * 0.5))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Theme.gradient(for: name, index: colorIndex), in: shape)
            }
        }
        .overlay(shape.strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: size * 0.1, y: size * 0.04)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}

/// Circular countdown in the account's colour; turns red for the last ten seconds.
struct CountdownRing: View {
    let period: Int
    let date: Date
    var tint: Color = .accentColor
    var size: CGFloat = 24

    var body: some View {
        let progress = TOTP.progress(period: period, date: date)
        let seconds = TOTP.remainingSeconds(period: period, date: date)
        let expiring = seconds <= 10
        let color: Color = expiring ? .red : tint
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: size * 0.13)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(expiring ? 0.4 : 0.15), radius: expiring ? 3 : 1)
            Text("\(seconds)")
                .font(Theme.codeFont(size: size * 0.46))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.25), value: expiring)
        .accessibilityLabel("Noch \(seconds) Sekunden gültig")
    }
}

/// The TOTP code in Dosis 800, tinted with the account's colour.
struct CodeText: View {
    let code: String?
    let expiring: Bool
    var tint: Color = .primary
    var size: CGFloat = 22

    var body: some View {
        Text(code.map(TOTP.format) ?? "–––  –––")
            .font(Theme.codeFont(size: size))
            .kerning(size * 0.02)
            .foregroundStyle(code == nil ? AnyShapeStyle(.tertiary) : expiring ? AnyShapeStyle(.red) : AnyShapeStyle(tint))
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.35), value: code)
    }
}

/// Keycap-style shortcut hint, e.g. [⌃⌥T].
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassSurface(cornerRadius: 6)
    }
}

/// Behind-window blur for the panels on systems without Liquid Glass.
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
