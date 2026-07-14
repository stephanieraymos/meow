import SwiftUI

/// Single-player practice. Same high-stakes identity — no hints — but you can
/// retry instantly. Great for learning the puzzle before racing Audie.
struct SoloGameView: View {
    let difficulty: Difficulty

    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: GameSession
    @State private var noteMode = false
    @State private var seed: UInt64

    init(difficulty: Difficulty) {
        self.difficulty = difficulty
        let s = UInt64.random(in: 0...UInt64.max)
        _seed = State(initialValue: s)
        let board = PuzzleGenerator.generate(seed: s, size: difficulty.size)
        _session = StateObject(wrappedValue: GameSession(board: board, allowedMistakes: 1))
    }

    var body: some View {
        ZStack {
            MeowTheme.backdrop.ignoresSafeArea()
            VStack(spacing: 16) {
                header
                BoardView(session: session,
                          onTap: { r, c in handleTap(r, c) },
                          onLongPress: { r, c in session.toggleBlock(row: r, col: c) })
                    .padding(.horizontal, 8)
                controls
            }
            .padding()

            if session.isOver { resultOverlay }
        }
        .navigationBarBackButtonHidden(false)
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Label("\(session.progress)/\(session.size)", systemImage: "pawprint.fill")
                    .font(.headline).foregroundStyle(.white)
                Spacer()
                Text("\(difficulty.title) · \(difficulty.subtitle)")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
            Text("One cat per row, column & color · no two cats touch · no hints")
                .font(.caption).foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("", selection: $noteMode) {
                Label("Cat", systemImage: "cat.fill").tag(false)
                Label("Note", systemImage: "xmark.square").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            Button {
                newPuzzle()
            } label: {
                Image(systemName: "arrow.clockwise").font(.headline)
                    .frame(width: 44, height: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.2))
        }
    }

    private func handleTap(_ r: Int, _ c: Int) {
        if noteMode {
            session.toggleBlock(row: r, col: c)
        } else {
            session.placeCat(row: r, col: c)
        }
    }

    private func newPuzzle() {
        dismiss()
    }

    private var resultOverlay: some View {
        ResultCard(
            won: session.isWon,
            title: session.isWon ? "Purr-fect!" : "One wrong cat…",
            subtitle: session.isWon
                ? "You solved the \(difficulty.subtitle) board."
                : "High stakes means no second chances. Try again?",
            primaryTitle: "New puzzle",
            primaryAction: { dismiss() },
            secondaryTitle: session.isWon ? nil : "Back",
            secondaryAction: { dismiss() }
        )
    }
}
