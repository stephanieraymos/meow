import SwiftUI

/// Renders the Meowdoku grid as rounded, colorful tiles and routes gestures:
///  - single tap  → toggle an "X" note (fires instantly)
///  - double tap  → place / remove a cat
///  - drag        → paint "X" notes across empty cells
struct BoardView: View {
    @ObservedObject var session: GameSession
    var style: CatStyle = CatStyles.all[0]
    var palette: MeowPalette = MeowPalettes.classic
    var spotlight: GameSession.Cell? = nil
    var onSingleTap: (Int, Int) -> Void
    var onDoubleTap: (Int, Int) -> Void
    var onPaint: (Int, Int) -> Void

    @State private var shakeAmount: CGFloat = 0
    @State private var paintedThisDrag: Set<Int> = []
    // Manual double-tap detection so a single tap (X) never waits on SwiftUI's
    // double-tap timeout — the X appears immediately.
    @State private var lastTapCell: Int = -1
    @State private var lastTapAt: Date = .distantPast

    private var board: MeowBoard { session.board }
    private var size: Int { board.size }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / CGFloat(size)

            VStack(spacing: 0) {
                ForEach(0..<size, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<size, id: \.self) { c in
                            cellView(r, c, cell: cell)
                                .frame(width: cell, height: cell)
                                .contentShape(Rectangle())
                                .onTapGesture { handleTap(r, c) }
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .coordinateSpace(name: "board")
            .simultaneousGesture(paintGesture(cell: cell))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: session.faultCell) { _, v in
            if v != nil { withAnimation(.linear(duration: 0.4)) { shakeAmount += 1 } }
        }
    }

    // MARK: - Gestures

    private func handleTap(_ r: Int, _ c: Int) {
        let key = r * size + c
        let now = Date()
        if key == lastTapCell, now.timeIntervalSince(lastTapAt) < 0.32 {
            lastTapCell = -1                 // consume, so a 3rd tap starts fresh
            onDoubleTap(r, c)
        } else {
            lastTapCell = key
            lastTapAt = now
            onSingleTap(r, c)
        }
    }

    private func paintGesture(cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named("board"))
            .onChanged { value in
                // Paint the cell the drag began on, then every new cell it enters.
                for loc in [value.startLocation, value.location] {
                    let c = Int(loc.x / cell), r = Int(loc.y / cell)
                    guard r >= 0, r < size, c >= 0, c < size else { continue }
                    let key = r * size + c
                    if paintedThisDrag.contains(key) { continue }
                    paintedThisDrag.insert(key)
                    onPaint(r, c)
                }
            }
            .onEnded { _ in paintedThisDrag.removeAll() }
    }

    // MARK: - Cell

    @ViewBuilder
    private func cellView(_ r: Int, _ c: Int, cell: CGFloat) -> some View {
        let mark = session.mark(row: r, col: c)
        let id = GameSession.Cell(row: r, col: c)
        let isFault = session.faultCell == id
        let hint = session.activeHint
        let isSpot = hint?.spotlight == id || spotlight == id
        let isTarget = hint?.targets.contains(id) ?? false
        let dimmed = hint != nil && !isSpot && !isTarget
        let region = board.regionID(row: r, col: c)
        let inset = cell * 0.045
        let radius = cell * 0.20

        ZStack {
            // Rounded tile with a soft top highlight for depth.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(isFault ? Color(red: 0.94, green: 0.35, blue: 0.33) : palette.color(region))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.02)],
                                             startPoint: .top, endPoint: .center))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.black.opacity(0.10), lineWidth: 1)
                )
                .padding(inset)
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)

            switch mark {
            case .cat:
                CatFace(style: style)
                    .frame(width: cell * 0.82, height: cell * 0.82)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            case .blocked:
                XMark().frame(width: cell * 0.44, height: cell * 0.44)
                    .transition(.opacity)
            case .empty:
                EmptyView()
            }

            // Dim everything except the spotlight and the cells being acted on.
            if dimmed {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.black.opacity(0.55))
                    .padding(inset)
            }
            // Preview the X's that "Apply" will place (exclude hints only).
            if isTarget, hint?.kind == .exclude {
                XMark().frame(width: cell * 0.46, height: cell * 0.46)
                    .modifier(PulseEffect())
            }
            // Spotlight ring on the cat being reasoned about, or a focused cell.
            if isSpot {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white, lineWidth: 3)
                    .padding(inset)
                    .modifier(PulseEffect())
            }
        }
        .animation(.snappy(duration: 0.18), value: mark)
        .modifier(Shake(animatableData: isFault ? shakeAmount : 0))
    }
}

/// A bold, rounded white "X" note — the reference game's look.
struct XMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Capsule().fill(.white).frame(width: s, height: s * 0.24).rotationEffect(.degrees(45))
                Capsule().fill(.white).frame(width: s, height: s * 0.24).rotationEffect(.degrees(-45))
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
        }
    }
}

/// Horizontal shake used to reject a wrong cat.
struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Gentle pulsing ring for a hint.
struct PulseEffect: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1.0 : 0.9)
            .opacity(on ? 1.0 : 0.45)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
