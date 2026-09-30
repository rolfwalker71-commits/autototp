import AppKit
import SwiftUI

/// Per-account colours, the bundled Dosis face and the Liquid Glass surfaces,
/// shared by every view. Glass needs macOS 26; older systems fall back to materials.
enum Theme {
    /// Two-stop gradients; an account keeps its colour everywhere (tile, ring, code, highlight).
    private static let palette: [(Color, Color)] = [
        (Color(red: 0.18, green: 0.53, blue: 0.99), Color(red: 0.36, green: 0.76, blue: 1.00)), // blau
        (Color(red: 0.45, green: 0.31, blue: 0.95), Color(red: 0.69, green: 0.50, blue: 1.00)), // violett
        (Color(red: 0.92, green: 0.28, blue: 0.60), Color(red: 1.00, green: 0.48, blue: 0.70)), // pink
        (Color(red: 0.95, green: 0.45, blue: 0.13), Color(red: 1.00, green: 0.68, blue: 0.22)), // orange
        (Color(red: 0.02, green: 0.66, blue: 0.53), Color(red: 0.25, green: 0.84, blue: 0.62)), // grün
        (Color(red: 0.01, green: 0.58, blue: 0.72), Color(red: 0.22, green: 0.78, blue: 0.90)), // türkis
        (Color(red: 0.62, green: 0.20, blue: 0.85), Color(red: 0.83, green: 0.42, blue: 0.98)), // magenta
        (Color(red: 0.87, green: 0.19, blue: 0.29), Color(red: 1.00, green: 0.42, blue: 0.42)), // rot
    ]

    static var paletteCount: Int { palette.count }

    static func colors(index: Int) -> (Color, Color) {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    /// A chosen colour wins; otherwise the name decides, so every account keeps one colour.
    static func colors(for name: String, index: Int? = nil) -> (Color, Color) {
        if let index {
            return colors(index: index)
        }
        let hash = name.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31 &+ $1.value) & 0x7FFF_FFFF }
        return palette[Int(hash) % palette.count]
    }

    static func tint(for name: String, index: Int? = nil) -> Color {
        colors(for: name, index: index).0
    }

    static func gradient(for name: String, index: Int? = nil) -> LinearGradient {
        let (start, end) = colors(for: name, index: index)
        return LinearGradient(colors: [end, start], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Dosis

    /// Dosis at weight 800 with tabular figures, bundled in Resources/Fonts.
    static func codeFont(size: CGFloat) -> Font {
        Font(codeNSFont(size: size))
    }

    static func codeNSFont(size: CGFloat) -> NSFont {
        let variations: [CFNumber: CFNumber] = [
            0x7767_6874 as CFNumber: 800 as CFNumber, // 'wght'
        ]
        let attributes: [CFString: Any] = [
            kCTFontNameAttribute: "Dosis" as CFString,
            kCTFontVariationAttribute: variations as CFDictionary,
            kCTFontFeatureSettingsAttribute: [
                [kCTFontFeatureTypeIdentifierKey: kNumberSpacingType,
                 kCTFontFeatureSelectorIdentifierKey: kMonospacedNumbersSelector],
            ] as CFArray,
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
        // Falls die eingebettete Schrift fehlt, bleibt der Code trotzdem lesbar.
        return font.familyName == "Dosis" ? font : .monospacedDigitSystemFont(ofSize: size, weight: .heavy)
    }
}

// MARK: - Liquid Glass surfaces

extension View {
    /// Tinted Liquid Glass on macOS 26+, tinted material below.
    func glassSurface(tint: Color? = nil, cornerRadius: CGFloat = 20, interactive: Bool = false) -> some View {
        modifier(GlassSurface(tint: tint, cornerRadius: cornerRadius, interactive: interactive))
    }
}

private struct GlassSurface: ViewModifier {
    let tint: Color?
    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(style, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .background(tint.map { $0.opacity(0.07) } ?? .clear, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
        }
    }

    @available(macOS 26.0, *)
    private var style: Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint.opacity(0.07))
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
}

/// Groups glass shapes so they blend into each other instead of stacking.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
