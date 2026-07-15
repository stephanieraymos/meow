import SwiftUI

/// Solo game host. Owns the current `GameMode`, and recreates the underlying
/// board screen (fresh session) when you replay or advance to the next level.
struct GameplayView: View {
    @State private var mode: GameMode
    @State private var replay = 0
    @Environment(\.dismiss) private var dismiss

    init(mode: GameMode) { _mode = State(initialValue: mode) }

    var body: some View {
        GameBoardScreen(mode: mode, onReplay: { replay += 1 }, onNext: nextAction, onExit: { dismiss() })
            .id("\(mode.seed)-\(replay)")
            .navigationBarBackButtonHidden(true)
    }

    private var nextAction: (() -> Void)? {
        if case .level(let i) = mode.kind, i < LevelCatalog.totalLevels {
            return { mode = .level(i + 1); replay = 0 }
        }
        return nil
    }
}

/// One board, one session. Handles play, hearts, hints, undo, timer, and result.
private struct GameBoardScreen: View {
    let mode: GameMode
    let onReplay: () -> Void
    let onNext: (() -> Void)?
    let onExit: () -> Void

    @StateObject private var session: GameSession
    @ObservedObject private var profile = PlayerProfile.shared
    @State private var recorded = false
    @State private var earnedStars = 0

    init(mode: GameMode, onReplay: @escaping () -> Void, onNext: (() -> Void)?, onExit: @escaping () -> Void) {
        self.mode = mode
        self.onReplay = onReplay
        self.onNext = onNext
        self.onExit = onExit
        let board = PuzzleGenerator.generate(seed: mode.seed, size: mode.size)
        _session = StateObject(wrappedValue: GameSession(board: board,
                                                         allowedMistakes: mode.allowedMistakes,
                                                         autoMark: PlayerProfile.shared.autoMarkOn))
    }

    var body: some View {
        ZStack {
            MeowTheme.backdrop.ignoresSafeArea()
            VStack(spacing: 14) {
                topBar
                header
                BoardView(session: session,
                          catGlyph: profile.catGlyph,
                          onSingleTap: { r, c in session.toggleBlock(row: r, col: c) },
                          onDoubleTap: { r, c in session.placeCat(row: r, col: c) },
                          onPaint: { r, c in session.paintBlock(row: r, col: c) })
                    .padding(.horizontal, 8)
                controls
            }
            .padding()

            if session.isOver { resultOverlay }
        }
        .onChange(of: session.isWon) { _, won in if won { recordWin() } }
        .onChange(of: session.isLost) { _, lost in if lost { recordLoss() } }
    }

    // MARK: Bars

    private var topBar: some View {
        HStack {
            Button { onExit() } label: { Image(systemName: "chevron.left").font(.headline) }
            Spacer()
            Text(mode.title).font(.headline).foregroundStyle(.white)
            Spacer()
            Button { onExit() } label: { Image(systemName: "xmark").font(.headline) }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                hearts
                Spacer()
                Label("\(session.progress)/\(session.size)", systemImage: "pawprint.fill")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.white)
                if mode.showsTimer {
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Label(timeString(session.elapsed), systemImage: "clock")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            Text("Double-tap = cat · tap = X · drag = mark · no hints in races")
                .font(.caption2).foregroundStyle(.white.opacity(0.55))
        }
    }

    private var hearts: some View {
        HStack(spacing: 3) {
            ForEach(0..<mode.allowedMistakes, id: \.self) { i in
                Image(systemName: i < session.heartsRemaining ? "heart.fill" : "heart")
                    .foregroundStyle(i < session.heartsRemaining ? .pink : .white.opacity(0.3))
                    .font(.subheadline)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                session.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(.white)
            .disabled(!session.canUndo)

            if mode.hintsAllowed {
                Button {
                    session.hint()
                } label: {
                    Label("Hint", systemImage: "lightbulb.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.yellow)
                .disabled(session.isOver)
            }
        }
        .frame(maxWidth: 320)
    }

    // MARK: Result

    private var resultOverlay: some View {
        ResultCard(
            won: session.isWon,
            title: resultTitle,
            subtitle: resultSubtitle,
            accessory: session.isWon ? AnyView(winAccessory) : nil,
            buttons: resultButtons
        )
    }

    private var winAccessory: some View {
        VStack(spacing: 12) {
            StarRow(stars: earnedStars)
            ShareLink(item: shareText) {
                Label("Share result", systemImage: "square.and.arrow.up")
                    .font(.subheadline.bold())
            }
            .tint(.white)
        }
    }

    /// Spoiler-free brag text (never reveals cat positions).
    private var shareText: String {
        let stars = String(repeating: "⭐️", count: earnedStars) + String(repeating: "▫️", count: 3 - earnedStars)
        var header = "Meowdoku · \(mode.title)"
        if case .daily(let key) = mode.kind { header = "Meowdoku Daily \(key)" }
        return """
        \(header)
        \(mode.size)×\(mode.size) solved in \(timeString(session.elapsed)) \(PlayerProfile.shared.catGlyph)
        \(stars)
        """
    }

    private var resultTitle: String {
        session.isWon ? "Purr-fect! 🎉" : "Out of hearts"
    }

    private var resultSubtitle: String {
        if session.isWon {
            var s = "Solved in \(timeString(session.elapsed))"
            if case .daily = mode.kind { s += " · 🔥 \(profile.dailyStreak)-day streak" }
            if case .timeAttack(let size) = mode.kind, let best = profile.timeAttackBest(size: size) {
                s += " · best \(timeString(best))"
            }
            return s
        }
        return "That was your last heart. Try again?"
    }

    private var resultButtons: [ResultButton] {
        var buttons: [ResultButton] = []
        if session.isWon, let onNext {
            buttons.append(ResultButton(title: "Next level", style: .prominent, tint: .green, action: onNext))
            buttons.append(ResultButton(title: "Replay", style: .bordered, tint: .white, action: onReplay))
        } else {
            buttons.append(ResultButton(
                title: session.isWon ? "Play again" : "Try again",
                style: .prominent, tint: session.isWon ? .green : .orange, action: onReplay))
        }
        buttons.append(ResultButton(title: "Back", style: .bordered, tint: .white, action: onExit))
        return buttons
    }

    // MARK: Recording

    private func recordWin() {
        guard !recorded else { return }
        recorded = true
        earnedStars = LevelCatalog.stars(mistakes: session.mistakes, hintsUsed: session.hintsUsed)
        profile.recordGame(won: true)
        let gc = GameCenter.shared
        switch mode.kind {
        case .level(let i):
            profile.completeLevel(i, stars: earnedStars, time: session.elapsed)
            gc.submitTime(session.elapsed, leaderboardID: GameCenter.Leaderboard.time(size: mode.size))
            if i >= 50 { gc.report(GameCenter.Achievement.level50) }
        case .daily(let key):
            profile.recordDaily(key: key, solved: true)
            gc.submitTime(session.elapsed, leaderboardID: GameCenter.Leaderboard.daily)
            if profile.dailyStreak >= 7 { gc.report(GameCenter.Achievement.streak7) }
        case .timeAttack(let s):
            profile.recordTimeAttack(size: s, time: session.elapsed)
            gc.submitTime(session.elapsed, leaderboardID: GameCenter.Leaderboard.time(size: s))
        case .freeplay:
            break
        }
        gc.report(GameCenter.Achievement.firstWin)
        if session.mistakes == 0 && session.hintsUsed == 0 { gc.report(GameCenter.Achievement.flawless) }
    }

    private func recordLoss() {
        guard !recorded else { return }
        recorded = true
        profile.recordGame(won: false)
        if case .daily(let key) = mode.kind { profile.recordDaily(key: key, solved: false) }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Three-star rating row.
struct StarRow: View {
    let stars: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .foregroundStyle(i < stars ? .yellow : .white.opacity(0.3))
                    .font(.title3)
            }
        }
    }
}
