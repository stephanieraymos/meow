import SwiftUI

/// Visual language for Meowdoku — region colors, cat glyphs, and shared styling.
enum MeowTheme {

    /// Distinct, cat-friendly region fills. Index by region id (mod count).
    /// Chosen for high mutual contrast and readability in light *and* dark mode.
    static let regionColors: [Color] = [
        Color(red: 0.98, green: 0.80, blue: 0.36), // marmalade
        Color(red: 0.55, green: 0.78, blue: 0.98), // sky
        Color(red: 0.99, green: 0.62, blue: 0.60), // salmon
        Color(red: 0.68, green: 0.86, blue: 0.62), // sage
        Color(red: 0.82, green: 0.70, blue: 0.96), // lilac
        Color(red: 0.98, green: 0.86, blue: 0.55), // cream
        Color(red: 0.60, green: 0.90, blue: 0.86), // seafoam
        Color(red: 0.96, green: 0.71, blue: 0.85), // blossom
        Color(red: 0.74, green: 0.80, blue: 0.55), // moss
        Color(red: 0.80, green: 0.76, blue: 0.72), // stone
    ]

    static func regionColor(_ id: Int) -> Color {
        regionColors[((id % regionColors.count) + regionColors.count) % regionColors.count]
    }

    static let catGlyph = "🐈"
    static let winGlyph = "🏆"
    static let loseGlyph = "🙀"

    static let gridLine = Color.black.opacity(0.16)
    static let regionBorder = Color.black.opacity(0.55)

    /// A warm, playful gradient used behind menus and result screens.
    static var backdrop: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.16, green: 0.13, blue: 0.24),
                Color(red: 0.28, green: 0.18, blue: 0.30),
            ],
            startPoint: .top, endPoint: .bottom
        )
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
