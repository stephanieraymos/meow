import SwiftUI

/// A lightweight, self-contained confetti burst — colored pieces that fall and
/// tumble. No assets, no dependencies.
struct ConfettiView: View {
    var count = 70
    private let palette = PlayerProfile.shared.palette.colors

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    ConfettiPiece(
                        color: palette[i % palette.count],
                        startX: CGFloat.random(in: 0...geo.size.width),
                        width: CGFloat.random(in: 6...11),
                        duration: Double.random(in: 2.0...3.6),
                        delay: Double.random(in: 0...1.4),
                        drift: CGFloat.random(in: -40...40),
                        height: geo.size.height)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ConfettiPiece: View {
    let color: Color
    let startX: CGFloat
    let width: CGFloat
    let duration: Double
    let delay: Double
    let drift: CGFloat
    let height: CGFloat
    @State private var fall = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: width, height: width * 0.55)
            .rotationEffect(.degrees(fall ? Double.random(in: 220...520) : 0))
            .position(x: startX + (fall ? drift : 0), y: fall ? height + 40 : -40)
            .opacity(fall ? 0.95 : 0)
            .onAppear {
                withAnimation(.linear(duration: duration).delay(delay).repeatForever(autoreverses: false)) {
                    fall = true
                }
            }
    }
}

/// A happy little jump/wiggle for a celebration hero.
struct JumpEffect: ViewModifier {
    @State private var up = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(up ? 1.02 : 0.88)
            .offset(y: up ? -10 : 4)
            .rotationEffect(.degrees(up ? 3 : -3))
            .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: up)
            .onAppear { up = true }
    }
}

/// A dejected head-shake + slump for a loss.
struct SlumpEffect: ViewModifier {
    @State private var phase = false
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(phase ? 6 : -6))
            .offset(y: phase ? 3 : 0)
            .grayscale(0.4)
            .animation(.easeInOut(duration: 0.35).repeatCount(6, autoreverses: true), value: phase)
            .onAppear { phase = true }
    }
}

/// The commiseration hero for a loss — a drawn cat that shakes its head, then
/// slumps. Same swap point as `CelebrationCat` (uses `sad_cat` if bundled).
struct CommiserationCat: View {
    var style: CatStyle = CatStyles.all[0]
    var body: some View {
        if Bundle.main.url(forResource: "sad_cat", withExtension: "usdz") != nil {
            CatSceneView(resource: "sad_cat")   // animated 3D cat, hangs its head
        } else if UIImage(named: "sad_cat") != nil {
            Image("sad_cat").resizable().scaledToFit().modifier(SlumpEffect())
        } else {
            CatFace(style: style).modifier(SlumpEffect())
        }
    }
}

/// The celebration hero. Uses a bundled image named "celebration_cat" if you add
/// one to the asset catalog (a rendered/animated cat like the reference), and
/// otherwise falls back to the drawn `CatFace`. This is the single swap point for
/// dropping in nicer art later.
struct CelebrationCat: View {
    var style: CatStyle = CatStyles.all[0]

    var body: some View {
        Group {
            if UIImage(named: "celebration_cat") != nil {
                Image("celebration_cat").resizable().scaledToFit()
            } else {
                CatFace(style: style)
            }
        }
        .modifier(JumpEffect())
    }
}
