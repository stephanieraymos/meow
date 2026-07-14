import SwiftUI

/// Renders the Meowdoku grid: colored regions, thick region outlines, placed
/// cats, and "X" notes. Reports taps and long-presses; the parent decides what
/// they mean (place cat vs. leave a note).
struct BoardView: View {
    @ObservedObject var session: GameSession
    var onTap: (Int, Int) -> Void
    var onLongPress: (Int, Int) -> Void

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
                                .onTapGesture { onTap(r, c) }
                                .onLongPressGesture(minimumDuration: 0.28) { onLongPress(r, c) }
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .overlay(RegionOutlines(regions: board.regions, size: size).stroke(MeowTheme.regionBorder, lineWidth: 2.5))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(MeowTheme.regionBorder, lineWidth: 3)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func cellView(_ r: Int, _ c: Int, cell: CGFloat) -> some View {
        let mark = session.mark(row: r, col: c)
        let isFault = session.faultCell == GameSession.Cell(row: r, col: c)
        ZStack {
            Rectangle()
                .fill(isFault ? Color.red.opacity(0.85) : MeowTheme.regionColor(board.regionID(row: r, col: c)))
            Rectangle()
                .stroke(MeowTheme.gridLine, lineWidth: 0.5)

            switch mark {
            case .cat:
                Text(MeowTheme.catGlyph)
                    .font(.system(size: cell * 0.62))
                    .minimumScaleFactor(0.5)
            case .blocked:
                Image(systemName: "xmark")
                    .font(.system(size: cell * 0.32, weight: .bold))
                    .foregroundStyle(.black.opacity(0.45))
            case .empty:
                EmptyView()
            }
        }
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
                // Draw the top edge if the neighbor above is a different region.
                if id(r - 1, c) != me {
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + cell, y: y))
                }
                // Left edge.
                if id(r, c - 1) != me {
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x, y: y + cell))
                }
                // Bottom edge (only need to add on the last row / boundary; interior
                // bottoms are covered by the next cell's top, but drawing twice is fine).
                if id(r + 1, c) != me {
                    path.move(to: CGPoint(x: x, y: y + cell))
                    path.addLine(to: CGPoint(x: x + cell, y: y + cell))
                }
                // Right edge.
                if id(r, c + 1) != me {
                    path.move(to: CGPoint(x: x + cell, y: y))
                    path.addLine(to: CGPoint(x: x + cell, y: y + cell))
                }
            }
        }
        return path
    }
}
