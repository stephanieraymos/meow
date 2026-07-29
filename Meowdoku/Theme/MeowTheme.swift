import SwiftUI

/// Visual language for Meowdoku — region colors, cat glyphs, and shared styling.
enum MeowTheme {

    /// Ten maximally-distinct region fills, ordered so consecutive region ids
    /// (which tend to sit next to each other) land far apart on the color wheel.
    /// No two are close, so regions are easy to tell apart at a glance.
    static let regionColors: [Color] = [
        Color(red: 0.96, green: 0.44, blue: 0.42), // coral / red
        Color(red: 0.16, green: 0.74, blue: 0.76), // teal
        Color(red: 0.98, green: 0.82, blue: 0.30), // gold
        Color(red: 0.62, green: 0.46, blue: 0.94), // violet
        Color(red: 0.38, green: 0.78, blue: 0.44), // green
        Color(red: 0.98, green: 0.52, blue: 0.82), // pink
        Color(red: 0.30, green: 0.60, blue: 0.96), // sky blue
        Color(red: 0.99, green: 0.60, blue: 0.24), // orange
        Color(red: 0.55, green: 0.60, blue: 0.74), // slate
        Color(red: 0.76, green: 0.54, blue: 0.38), // brown
    ]

    static func regionColor(_ id: Int) -> Color {
        regionColors[((id % regionColors.count) + regionColors.count) % regionColors.count]
    }

    static let catGlyph = "🐈"
    static let winGlyph = "🏆"
    static let loseGlyph = "🙀"

    static let gridLine = Color.black.opacity(0.16)
    static let regionBorder = Color.black.opacity(0.55)

    /// Primary text/foreground — white in dark mode, near-black in light mode.
    static let ink = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? .white : UIColor(white: 0.13, alpha: 1)
    })
    /// Translucent card fill that reads on either backdrop.
    static let panel = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.12)
            : UIColor(red: 0.32, green: 0.22, blue: 0.42, alpha: 0.09)
    })

    /// Backdrop behind menus and the board — plum in dark mode, warm cream in
    /// light mode (matching the original Meowdoku's cozy off-white).
    static var backdrop: LinearGradient {
        LinearGradient(
            colors: [
                Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark
                    ? UIColor(red: 0.16, green: 0.13, blue: 0.24, alpha: 1)
                    : UIColor(red: 0.965, green: 0.935, blue: 0.895, alpha: 1) }),
                Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark
                    ? UIColor(red: 0.28, green: 0.18, blue: 0.30, alpha: 1)
                    : UIColor(red: 0.945, green: 0.905, blue: 0.86, alpha: 1) }),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// The board's container card + HUD pills — pure white in light mode, a soft
    /// translucent panel in dark mode.
    static var card: Color {
        Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.10)
            : UIColor(white: 1, alpha: 1) })
    }
}

/// User-selectable appearance.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Grid difficulty presets shown when starting a game.
enum Difficulty: Int, CaseIterable, Identifiable {
    case easy = 6
    case normal = 8
    case hard = 10

    var id: Int { rawValue }
    var size: Int { rawValue }
    var title: String {
        switch self {
        case .easy:   return "Easy"
        case .normal: return "Normal"
        case .hard:   return "Hard"
        }
    }
    var subtitle: String { "\(rawValue)×\(rawValue)" }
}
