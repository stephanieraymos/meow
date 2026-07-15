import SwiftUI

/// A selectable cat "piece" — a fur palette for the drawn `CatFace`. Purely
/// cosmetic.
struct CatStyle: Identifiable, Equatable {
    let id: String
    let name: String
    let fur: Color        // head + ears
    let belly: Color      // muzzle / chest patch
    let innerEar: Color   // inner-ear pink
    let eye: Color        // iris
}

enum CatStyles {
    static let all: [CatStyle] = [
        CatStyle(id: "tuxedo", name: "Tuxedo",
                 fur: Color(red: 0.14, green: 0.15, blue: 0.18),
                 belly: Color(red: 0.97, green: 0.97, blue: 0.98),
                 innerEar: Color(red: 0.96, green: 0.68, blue: 0.72),
                 eye: Color(red: 0.55, green: 0.82, blue: 0.45)),
        CatStyle(id: "orange", name: "Marmalade",
                 fur: Color(red: 0.95, green: 0.60, blue: 0.26),
                 belly: Color(red: 0.99, green: 0.92, blue: 0.80),
                 innerEar: Color(red: 0.97, green: 0.72, blue: 0.62),
                 eye: Color(red: 0.42, green: 0.68, blue: 0.40)),
        CatStyle(id: "grey", name: "Ash",
                 fur: Color(red: 0.55, green: 0.58, blue: 0.64),
                 belly: Color(red: 0.94, green: 0.95, blue: 0.97),
                 innerEar: Color(red: 0.96, green: 0.72, blue: 0.74),
                 eye: Color(red: 0.90, green: 0.72, blue: 0.30)),
        CatStyle(id: "black", name: "Void",
                 fur: Color(red: 0.12, green: 0.12, blue: 0.15),
                 belly: Color(red: 0.20, green: 0.20, blue: 0.24),
                 innerEar: Color(red: 0.55, green: 0.42, blue: 0.46),
                 eye: Color(red: 0.98, green: 0.80, blue: 0.28)),
        CatStyle(id: "cream", name: "Cream",
                 fur: Color(red: 0.95, green: 0.88, blue: 0.76),
                 belly: Color(red: 0.99, green: 0.96, blue: 0.90),
                 innerEar: Color(red: 0.97, green: 0.74, blue: 0.72),
                 eye: Color(red: 0.45, green: 0.62, blue: 0.85)),
        CatStyle(id: "calico", name: "Calico",
                 fur: Color(red: 0.86, green: 0.52, blue: 0.34),
                 belly: Color(red: 0.98, green: 0.94, blue: 0.88),
                 innerEar: Color(red: 0.96, green: 0.70, blue: 0.66),
                 eye: Color(red: 0.50, green: 0.72, blue: 0.42)),
    ]

    static func style(_ id: String) -> CatStyle {
        all.first { $0.id == id } ?? all[0]
    }
}

/// A cute, flat-illustration cat face drawn entirely with SwiftUI shapes — no
/// image assets. Scales to fill whatever frame it's given.
struct CatFace: View {
    var style: CatStyle = CatStyles.all[0]
    /// Drives a slow blink so a board full of cats feels alive.
    @State private var blink = false

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                ears(s)
                head(s)
                muzzle(s)
                eyes(s)
                nose(s)
                whiskers(s)
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            // Occasional, staggered blink so a board of cats feels alive.
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0...3) * 1_000_000_000))
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 3...6) * 1_000_000_000))
                withAnimation(.easeInOut(duration: 0.09)) { blink = true }
                try? await Task.sleep(nanoseconds: 110_000_000)
                withAnimation(.easeInOut(duration: 0.12)) { blink = false }
            }
        }
    }

    // MARK: Pieces (positions are fractions of side `s`)

    private func ears(_ s: CGFloat) -> some View {
        ZStack {
            ear(s, left: true)
            ear(s, left: false)
        }
    }

    private func ear(_ s: CGFloat, left: Bool) -> some View {
        let dir: CGFloat = left ? -1 : 1
        return ZStack {
            Triangle()
                .fill(style.fur)
                .frame(width: s * 0.34, height: s * 0.34)
            Triangle()
                .fill(style.innerEar)
                .frame(width: s * 0.17, height: s * 0.17)
                .offset(y: s * 0.05)
        }
        .rotationEffect(.degrees(Double(dir) * 18))
        .offset(x: dir * s * 0.24, y: -s * 0.30)
    }

    private func head(_ s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: s * 0.34, style: .continuous)
            .fill(style.fur)
            .frame(width: s * 0.80, height: s * 0.72)
            .offset(y: s * 0.02)
    }

    private func muzzle(_ s: CGFloat) -> some View {
        Ellipse()
            .fill(style.belly)
            .frame(width: s * 0.56, height: s * 0.40)
            .offset(y: s * 0.16)
    }

    private func eyes(_ s: CGFloat) -> some View {
        HStack(spacing: s * 0.16) {
            eye(s)
            eye(s)
        }
        .offset(y: -s * 0.04)
    }

    private func eye(_ s: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(.white).frame(width: s * 0.15, height: s * 0.19)
            Ellipse().fill(style.eye).frame(width: s * 0.11, height: s * 0.15)
            Capsule().fill(.black).frame(width: s * 0.045, height: s * 0.13)
            Circle().fill(.white).frame(width: s * 0.03, height: s * 0.03).offset(x: s * 0.02, y: -s * 0.03)
        }
        .scaleEffect(y: blink ? 0.1 : 1.0, anchor: .center)
    }

    private func nose(_ s: CGFloat) -> some View {
        Triangle()
            .fill(Color(red: 0.95, green: 0.55, blue: 0.60))
            .frame(width: s * 0.09, height: s * 0.07)
            .rotationEffect(.degrees(180))
            .offset(y: s * 0.12)
    }

    private func whiskers(_ s: CGFloat) -> some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                let y = s * (0.14 + Double(i) * 0.06)
                Capsule().fill(.black.opacity(0.25)).frame(width: s * 0.22, height: s * 0.012).offset(x: -s * 0.30, y: y)
                Capsule().fill(.black.opacity(0.25)).frame(width: s * 0.22, height: s * 0.012).offset(x: s * 0.30, y: y)
            }
        }
    }
}

/// Upward-pointing triangle.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
