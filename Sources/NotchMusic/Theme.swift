import AppKit
import SwiftUI

/// Color tokens. Collapsed and peek states are always dark (they must merge
/// with the black camera housing); the open panel is light by default, with
/// a dark variant in the right-click menu.
struct Palette {
    var surface: Color
    var ink: Color            // primary text and glyphs
    var inkSecondary: Color
    var inkTertiary: Color
    var wash: Color           // hover discs, fields, tracks
    var accent: Color         // from the cover, tuned for contrast on `surface`
    var onAccent: Color       // glyph on an accent fill
    var isLight: Bool

    static func dark(accent: NSColor) -> Palette {
        Palette(surface: .black, ink: .white, inkSecondary: .white.opacity(0.6),
                inkTertiary: .white.opacity(0.42), wash: .white.opacity(0.1),
                accent: Color(nsColor: accent), onAccent: .black, isLight: false)
    }

    static func light(accent: NSColor) -> Palette {
        let ink = Color(red: 0.11, green: 0.11, blue: 0.12)
        return Palette(surface: Color(red: 0.965, green: 0.965, blue: 0.972), ink: ink,
                       inkSecondary: ink.opacity(0.6), inkTertiary: ink.opacity(0.42), wash: ink.opacity(0.06),
                       accent: Color(nsColor: deepened(accent)), onAccent: .white, isLight: true)
    }

    /// Frosted glass: white ink over a blurred desktop, white as the accent
    /// (solid white play button with a dark glyph), like the reference design.
    static var glass: Palette {
        Palette(surface: .clear, ink: .white, inkSecondary: .white.opacity(0.78),
                inkTertiary: .white.opacity(0.6), wash: .white.opacity(0.14),
                accent: .white, onAccent: Color(red: 0.16, green: 0.17, blue: 0.2), isLight: false)
    }

    /// The cover accent is picked to glow on black; on off-white it needs to be
    /// darker to keep contrast (WCAG AA against the surface), same hue.
    private static func deepened(_ c: NSColor) -> NSColor {
        guard let rgb = c.usingColorSpace(.deviceRGB) else { return .black }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        if s < 0.15 { return NSColor(white: 0.12, alpha: 1) }   // greyscale cover: use ink
        return NSColor(hue: h, saturation: max(s, 0.55), brightness: 0.52, alpha: 1)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.dark(accent: .white)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
