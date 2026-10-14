import AppKit
import SwiftUI

/// Design tokens. Dark mode is the primary target: calm surfaces, one restrained accent.
enum Theme {
    /// Soft periwinkle. Slightly deeper in light mode so it keeps contrast on white.
    static let accent = Color(nsColor: NSColor(name: "PortlyAccent") { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.62, green: 0.64, blue: 1.00, alpha: 1)
            : NSColor(srgbRed: 0.35, green: 0.36, blue: 0.86, alpha: 1)
    })

    static let danger = Color(nsColor: NSColor(name: "PortlyDanger") { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 1.00, green: 0.50, blue: 0.50, alpha: 1)
            : NSColor(srgbRed: 0.82, green: 0.20, blue: 0.20, alpha: 1)
    })

    static let warning = Color(nsColor: NSColor(name: "PortlyWarning") { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 1.00, green: 0.78, blue: 0.45, alpha: 1)
            : NSColor(srgbRed: 0.72, green: 0.45, blue: 0.05, alpha: 1)
    })

    /// Neutral fills layered over the window material.
    static let hoverFill = Color.primary.opacity(0.055)
    static let pressedFill = Color.primary.opacity(0.09)
    static let hairline = Color.primary.opacity(0.08)
    static let fieldFill = Color.primary.opacity(0.06)

    static let rowRadius: CGFloat = 10
    static let popoverWidth: CGFloat = 360

    static func portFont(size: CGFloat = 15) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }

    static let titleFont = Font.system(size: 13, weight: .medium)
    static let metaFont = Font.system(size: 11).monospacedDigit()
    static let pillFont = Font.system(size: 10, weight: .semibold, design: .rounded)
    static var logFont: NSFont { .monospacedSystemFont(ofSize: 11, weight: .regular) }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
    }
}

extension Animation {
    /// The app's standard spring, or a short fade when Reduce Motion is on.
    static func localhost(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)
    }
}
