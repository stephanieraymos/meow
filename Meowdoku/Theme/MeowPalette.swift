import SwiftUI

/// A selectable set of 10 region colors. Purely cosmetic and per-player, so it
/// never affects a race's fairness (both boards share the same regions).
/// Ordered so consecutive region ids land far apart and never look alike.
struct MeowPalette: Identifiable, Equatable {
    let id: String
    let name: String
    let colors: [Color]

    func color(_ regionID: Int) -> Color {
        colors[((regionID % colors.count) + colors.count) % colors.count]
    }

    /// A plain-English name for a region's color, used in hint text. Classified
    /// from hue/brightness so it works for any palette.
    func name(_ regionID: Int) -> String { MeowPalette.name(for: color(regionID)) }

    /// Unique color names for regions 0..<count. Where a clustered palette maps
    /// two regions to the same base name, they're qualified by brightness
    /// ("deep orange" / "light orange") so every region reads distinctly in hints.
    func regionNames(count: Int) -> [String] {
        let base = (0..<count).map { name($0) }
        let bright = (0..<count).map { MeowPalette.brightness(of: color($0)) }
        var byName: [String: [Int]] = [:]
        for i in 0..<count { byName[base[i], default: []].append(i) }
        var out = base
        for (nm, idxs) in byName where idxs.count > 1 {
            let sorted = idxs.sorted { bright[$0] < bright[$1] }   // darkest first
            for (rank, region) in sorted.enumerated() {
                switch (sorted.count, rank) {
                case (2, 0): out[region] = "deep \(nm)"
                case (2, 1): out[region] = "light \(nm)"
                case (3, 0): out[region] = "deep \(nm)"
                case (3, 1): out[region] = nm
                case (3, 2): out[region] = "light \(nm)"
                default:     out[region] = "\(nm) \(rank + 1)"
                }
            }
        }
        return out
    }

    static func brightness(of color: Color) -> CGFloat {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return v
    }

    static func name(for color: Color) -> String {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        let hue = h * 360
        // Near-greys, then muted mid-tones that would otherwise collide with a
        // vivid sibling of the same hue (slate ≠ blue, brown ≠ orange).
        if s < 0.16 { return v > 0.72 ? "white" : (v < 0.35 ? "charcoal" : "grey") }
        if s < 0.34, hue >= 190, hue < 260 { return "slate" }
        if (hue < 45 || hue >= 340), s < 0.62, v < 0.85 { return "brown" }
        switch hue {
        case ..<15, 345...: return "red"
        case ..<40:  return "orange"
        case ..<65:  return v < 0.62 ? "olive" : "yellow"
        case ..<95:  return "lime"
        case ..<150: return "green"
        case ..<175: return "teal"
        case ..<200: return "cyan"
        case ..<245: return "blue"
        case ..<275: return "indigo"
        case ..<310: return "purple"
        case ..<335: return "magenta"
        default:     return "pink"
        }
    }
}

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

enum MeowPalettes {
    static let classic = MeowPalette(id: "classic", name: "Classic", colors: [
        rgb(0.96, 0.44, 0.42), rgb(0.16, 0.74, 0.76), rgb(0.98, 0.82, 0.30),
        rgb(0.62, 0.46, 0.94), rgb(0.38, 0.78, 0.44), rgb(0.98, 0.52, 0.82),
        rgb(0.30, 0.60, 0.96), rgb(0.99, 0.60, 0.24), rgb(0.55, 0.60, 0.74),
        rgb(0.76, 0.54, 0.38),
    ])

    static let bright = MeowPalette(id: "bright", name: "Bright", colors: [
        rgb(0.98, 0.30, 0.35), rgb(0.10, 0.72, 0.85), rgb(1.00, 0.78, 0.12),
        rgb(0.58, 0.35, 0.95), rgb(0.25, 0.78, 0.38), rgb(1.00, 0.45, 0.72),
        rgb(0.18, 0.52, 0.98), rgb(1.00, 0.52, 0.14), rgb(0.30, 0.82, 0.72),
        rgb(0.85, 0.42, 0.30),
    ])

    static let neon = MeowPalette(id: "neon", name: "Neon", colors: [
        rgb(1.00, 0.10, 0.55), rgb(0.05, 0.95, 0.92), rgb(0.80, 1.00, 0.12),
        rgb(0.68, 0.15, 1.00), rgb(0.15, 1.00, 0.42), rgb(1.00, 0.35, 0.82),
        rgb(0.15, 0.55, 1.00), rgb(1.00, 0.50, 0.05), rgb(0.00, 0.95, 0.75),
        rgb(1.00, 0.22, 0.28),
    ])

    static let retro = MeowPalette(id: "retro", name: "Retro", colors: [
        rgb(0.87, 0.56, 0.24), rgb(0.36, 0.56, 0.50), rgb(0.90, 0.76, 0.42),
        rgb(0.56, 0.42, 0.56), rgb(0.56, 0.66, 0.36), rgb(0.86, 0.52, 0.44),
        rgb(0.42, 0.52, 0.62), rgb(0.82, 0.46, 0.28), rgb(0.70, 0.66, 0.50),
        rgb(0.56, 0.40, 0.34),
    ])

    static let dark = MeowPalette(id: "dark", name: "Dark", colors: [
        rgb(0.72, 0.28, 0.34), rgb(0.16, 0.48, 0.52), rgb(0.68, 0.58, 0.24),
        rgb(0.44, 0.32, 0.64), rgb(0.24, 0.52, 0.38), rgb(0.68, 0.36, 0.54),
        rgb(0.24, 0.42, 0.64), rgb(0.74, 0.46, 0.26), rgb(0.42, 0.46, 0.54),
        rgb(0.52, 0.36, 0.30),
    ])

    static let all: [MeowPalette] = [classic, bright, neon, retro, dark]

    static func palette(_ id: String) -> MeowPalette {
        all.first { $0.id == id } ?? classic
    }
}
