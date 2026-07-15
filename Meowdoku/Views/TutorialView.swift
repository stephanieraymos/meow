import SwiftUI

/// A short, on-rails tutorial that teaches the four rules by having the player
/// place the glowing cat at each step — including the signature no-touching rule.
struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profile = PlayerProfile.shared
    @StateObject private var session: GameSession

    init() {
        // A fixed, gentle 6×6 board so the guidance always lines up.
        let board = PuzzleGenerator.generate(seed: 0xC0FFEE, size: 6)
        _session = StateObject(wrappedValue: GameSession(board: board, allowedMistakes: 99, autoMark: false))
    }

    /// The next cat to place: the first row (top to bottom) still missing its cat.
    private var target: GameSession.Cell? {
        for r in 0..<session.size where session.mark(row: r, col: session.board.solution[r]) != .cat {
            return GameSession.Cell(row: r, col: session.board.solution[r])
        }
        return nil
    }

    var body: some View {
        ZStack {
            MeowTheme.backdrop.ignoresSafeArea()
            VStack(spacing: 18) {
                header
                instructionBanner
                BoardView(session: session,
                          style: profile.catStyle,
                          palette: profile.palette,
                          spotlight: session.isWon ? nil : target,
                          onSingleTap: { _, _ in },
                          onDoubleTap: { r, c in placeIfTarget(r, c) },
                          onPaint: { _, _ in })
                    .padding(.horizontal, 8)
                Spacer()
                if session.isWon { doneButton } else { skipButton }
            }
            .padding()
        }
    }

    private var header: some View {
        HStack {
            Text("How to play").font(.headline).foregroundStyle(MeowTheme.ink)
            Spacer()
            Text("\(session.progress)/\(session.size)")
                .font(.subheadline.monospacedDigit()).foregroundStyle(MeowTheme.ink.opacity(0.8))
        }
    }

    private var instructionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("🐱").font(.title)
            Text(message)
                .font(.callout).foregroundStyle(MeowTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MeowTheme.ink.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private var message: String {
        if session.isWon { return "That's Meowdoku! Every row, column and color has exactly one cat, and none of them touch. You're ready. 🎉" }
        switch session.progress {
        case 0: return "Welcome! Double-tap the glowing cell to place your first cat. Each ROW gets exactly one cat."
        case 1: return "Each COLUMN gets one cat too — never two cats in the same column."
        case 2: return "Every COLOR region also holds exactly one cat. Place the next glowing cat."
        case 3: return "The signature rule: cats can't TOUCH — not even diagonally. The glowing cell is always safe."
        default: return "You've got it — keep placing the glowing cats to finish the board."
        }
    }

    private func placeIfTarget(_ r: Int, _ c: Int) {
        guard let t = target, t.row == r, t.col == c else { return }
        session.placeCat(row: r, col: c)
    }

    private var doneButton: some View {
        Button {
            profile.tutorialSeen = true
            dismiss()
        } label: {
            Text("Start playing").font(.headline).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).tint(.pink)
    }

    private var skipButton: some View {
        Button {
            profile.tutorialSeen = true
            dismiss()
        } label: {
            Text("Skip").foregroundStyle(MeowTheme.ink.opacity(0.7))
        }
    }
}
