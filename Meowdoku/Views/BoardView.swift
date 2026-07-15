import SwiftUI

/// Renders the Meowdoku grid and routes gestures:
///  - single tap  → toggle an "X" note (or clear a cat)
///  - double tap  → place / remove a cat
///  - drag        → paint "X" notes across empty cells
struct BoardView: View {
    @ObservedObject var session: GameSession
    var catGlyph: String = "🐱"
    var spotlight: GameSession.Cell? = nil
    var onSingleTap: (Int, Int) -> Void
    var onDoubleTap: (Int, Int) -> Void
    var onPaint: (Int, Int) -> Void

    @State private var shakeAmount: CGFloat = 0
    @State private var paintedThisDrag: Set<Int> = []

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
                                .onTapGesture(count: 2) { onDoubleTap(r, c) }
                                .onTapGesture(count: 1) { onSingleTap(r, c) }
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .coordinateSpace(name: "board")
            .simultaneousGesture(paintGesture(cell: cell))
            .overlay(RegionOutlines(regions: board.regions, size: size).stroke(MeowTheme.regionBorder, lineWidth: 2.5))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(MeowTheme.regionBorder, lineWidth: 3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: session.faultCell) { _, newValue in
            if newValue != nil { withAnimation(.linear(duration: 0.45)) { shakeAmount += 1 } }
        }
    }

    /// Drag beyond a small threshold paints X's on the empty cells it passes over.
    private func paintGesture(cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .named("board"))
            .onChanged { value in
                let c = Int(value.location.x / cell)
                let r = Int(value.location.y / cell)
                guard r >= 0, r < size, c >= 0, c < size else { return }
                let key = r * size + c
                if paintedThisDrag.contains(key) { return }
                paintedThisDrag.insert(key)
                onPaint(r, c)
            }
            .onEnded { _ in paintedThisDrag.removeAll() }
    }

    @ViewBuilder
    private func cellView(_ r: Int, _ c: Int, cell: CGFloat) -> some View {
        let mark = session.mark(row: r, col: c)
        let cellID = GameSession.Cell(row: r, col: c)
        let isFault = session.faultCell == cellID
        let isHint = session.hintCell == cellID || spotlight == cellID

        ZStack {
            Rectangle()
                .fill(isFault ? Color.red.opacity(0.85) : MeowTheme.regionColor(board.regionID(row: r, col: c)))
            Rectangle().stroke(MeowTheme.gridLine, lineWidth: 0.5)

            if isHint {
                RoundedRectangle(cornerRadius: cell * 0.14)
                    .stroke(Color.white, lineWidth: 3)
                    .padding(cell * 0.08)
                    .modifier(PulseEffect())
            }

            switch mark {
            case .cat:
                Text(catGlyph)
                    .font(.system(size: cell * 0.62))
                    .minimumScaleFactor(0.5)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            case .blocked:
                Image(systemName: "xmark")
                    .font(.system(size: cell * 0.32, weight: .bold))
                    .foregroundStyle(.black.opacity(0.45))
                    .transition(.scale.combined(with: .opacity))
            case .empty:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: mark)
        .modifier(Shake(animatableData: isFault ? shakeAmount : 0))
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
            .scaleEffect(on ? 1.0 : 0.88)
            .opacity(on ? 1.0 : 0.4)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// A Shape that traces the boundaries *between* differently-colored regions
/// (and the outer edge), so regions read as bold outlined territories.
struct RegionOutlines: Shape {
    let regions: [[Int]]
    let size: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cell = min(rect.width, rect.height) / CGFloat(size)
        func id(_ r: Int, _ c: Int) -> Int? {
            guard r >= 0, r < size, c >= 0, c < size else { return nil }
            return regions[r][c]
        }
        for r in 0..<size {
            for c in 0..<size {
                let me = regions[r][c]
                let x = CGFloat(c) * cell
                let y = CGFloat(r) * cell
                if id(r - 1, c) != me {
                    path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: x + cell, y: y))
                }
                if id(r, c - 1) != me {
                    path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: x, y: y + cell))
                }
                if id(r + 1, c) != me {
                    path.move(to: CGPoint(x: x, y: y + cell)); path.addLine(to: CGPoint(x: x + cell, y: y + cell))
                }
                if id(r, c + 1) != me {
                    path.move(to: CGPoint(x: x + cell, y: y)); path.addLine(to: CGPoint(x: x + cell, y: y + cell))
                }
            }
        }
        return path
    }
}
