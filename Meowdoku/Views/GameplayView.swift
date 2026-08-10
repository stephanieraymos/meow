import SwiftUI

/// Solo game host. Owns the current `GameMode`, and recreates the underlying
/// board screen (fresh session) when you replay or advance to the next level.
struct GameplayView: View {
    @State private var mode: GameMode
    @State private var replay = 0
    @Environment(\.dismiss) private var dismiss

    init(mode: GameMode) { _mode = State(initialValue: mode) }

    var body: some View {
        GameBoardLoader(mode: mode, onReplay: { replay += 1 }, onNext: nextAction, onExit: { dismiss() })
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

/// Builds the board **off the main thread**, then hands it to the board screen.
/// Difficulty-matched generation runs a candidate search that can take a few
/// hundred milliseconds at 10×10 — doing that inline in a view's `init` froze the
/// UI on "New game" and re-ran on every re-render.
private struct GameBoardLoader: View {
    let mode: GameMode
    let onReplay: () -> Void
    let onNext: (() -> Void)?
    let onExit: () -> Void

    @State private var session: GameSession?

    var body: some View {
        ZStack {
            MeowTheme.backdrop.ignoresSafeArea()
            if let session {
                GameBoardScreen(mode: mode, session: session,
                                onReplay: onReplay, onNext: onNext, onExit: onExit)
            } else {
                generating
            }
        }
        .task { await load() }
    }

    private var generating: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large).tint(MeowTheme.ink)
            Text("Setting up your \(mode.size)×\(mode.size) board…")
                .font(.headline).foregroundStyle(MeowTheme.ink)
            Text("Every puzzle is checked to have exactly one solution, so it's always solvable without guessing.")
                .font(.footnote).foregroundStyle(MeowTheme.ink.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
        }
    }

    private func load() async {
        guard session == nil else { return }
        let mode = self.mode
        // Palette naming touches UIColor, so read it here on the main actor.
        let autoMark = PlayerProfile.shared.autoMarkOn
        let names = PlayerProfile.shared.palette.regionNames(count: mode.size)
        let board = await Task.detached(priority: .userInitiated) { () -> MeowBoard in
            if let target = mode.difficultyTarget {
                return PuzzleGenerator.generate(seed: mode.seed, size: mode.size, target: target)
            }
            return PuzzleGenerator.generate(seed: mode.seed, size: mode.size)
        }.value
        session = GameSession(board: board, allowedMistakes: mode.allowedMistakes,
                              autoMark: autoMark, colorNames: names)
    }
}

/// One board, one session. Handles play, hearts, hints, undo, timer, and result.
private struct GameBoardScreen: View {
    let mode: GameMode
    @ObservedObject var session: GameSession
    let onReplay: () -> Void
    let onNext: (() -> Void)?
    let onExit: () -> Void

    @ObservedObject private var profile = PlayerProfile.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var recorded = false
    @State private var earnedStars = 0
    @State private var earnedScore = 0
    @State private var confirmExit = false

    /// Warm brown used for headers/labels — matches the original's cozy ink.
    private let brand = Color(red: 0.44, green: 0.31, blue: 0.27)

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                topBar
                statusRow
                ruleCards
                boardCard
                    .allowsHitTesting(session.activeHint == nil)
                controls
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.top, 4)

            if let hint = session.activeHint { hintPopover(hint) }
            if session.isOver { resultOverlay }
        }
        .onChange(of: session.isWon) { _, won in if won { recordWin() } }
        .onChange(of: session.isLost) { _, lost in if lost { recordLoss() } }
        // Don't let the clock run while the app is backgrounded — otherwise
        // putting the phone down destroys a best time or a Time Attack score.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.resumeTimer() } else { session.pauseTimer() }
        }
        .confirmationDialog("Leave this puzzle?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { onExit() }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("Your cats and X marks on this board will be lost.")
        }
    }

    /// Bail out immediately if nothing would be lost; otherwise confirm.
    private func requestExit() {
        if session.isOver || !session.canUndo { onExit() } else { confirmExit = true }
    }

    // MARK: Chrome

    private func roundButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.headline.weight(.semibold))
                .foregroundStyle(brand)
                .frame(width: 44, height: 44)   // Apple's minimum tap target
                .background(MeowTheme.card, in: Circle())
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
    }

    /// Level / Score header, flanked by round back + close buttons (the original's
    /// top bar). Non-campaign modes show their title in place of the stats.
    private var topBar: some View {
        HStack(alignment: .center) {
            roundButton("chevron.left") { requestExit() }
            Spacer()
            if case .level(let i) = mode.kind {
                HStack(spacing: 36) {
                    headerStat("Level", "\(i)")
                    headerStat("Score", "\(runningScore)")
                }
            } else {
                Text(mode.title).font(.title2.weight(.bold)).foregroundStyle(brand)
            }
            Spacer()
            roundButton("xmark") { requestExit() }
        }
    }

    private func headerStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(brand.opacity(0.75))
            Text(value).font(.title.weight(.heavy)).monospacedDigit().foregroundStyle(brand)
        }
    }

    /// A live, display-only score that ticks up as cats land (the final award is
    /// computed at win). Keeps the header's "Score" alive like the original.
    private var runningScore: Int {
        session.isWon ? earnedScore
                      : max(0, session.progress * 120 - session.mistakes * 40 - session.hintsUsed * 30)
    }

    /// Cat progress + hearts (+ timer) pills — the original's status row.
    private var statusRow: some View {
        HStack(spacing: 10) {
            pill {
                HStack(spacing: 6) {
                    Image(systemName: "cat.fill").font(.subheadline).foregroundStyle(brand)
                    (Text("\(session.progress)")
                        .foregroundStyle(session.progress >= session.size ? Color.green : brand)
                     + Text("/\(session.size)").foregroundStyle(brand.opacity(0.7)))
                        .font(.subheadline.weight(.bold)).monospacedDigit()
                }
            }
            Spacer()
            if mode.showsTimer {
                pill {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Label(timeString(session.elapsed), systemImage: "clock")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(brand.opacity(0.8))
                    }
                }
            }
            pill { hearts }
        }
    }

    private func pill<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(MeowTheme.card, in: Capsule())
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    private var hearts: some View {
        HStack(spacing: 3) {
            ForEach(0..<mode.allowedMistakes, id: \.self) { i in
                Image(systemName: i < session.heartsRemaining ? "heart.fill" : "heart")
                    .foregroundStyle(i < session.heartsRemaining ? .pink : brand.opacity(0.25))
                    .font(.subheadline)
            }
        }
    }

    /// The always-visible rules strip (the original's three rule cards).
    private var ruleCards: some View {
        HStack(spacing: 8) {
            ruleCard(.color, "1 Cat per color")
            ruleCard(.line,  "1 Cat per row & column")
            ruleCard(.touch, "Cats can't touch")
        }
        .padding(10)
        .background(MeowTheme.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func ruleCard(_ kind: RuleKind, _ text: String) -> some View {
        HStack(spacing: 7) {
            MiniRuleGrid(kind: kind)
            Text(text).font(.caption2.weight(.medium)).foregroundStyle(brand)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MeowTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The board inside its white rounded card (the original's board container).
    private var boardCard: some View {
        BoardView(session: session,
                  style: profile.catStyle,
                  palette: profile.palette,
                  onSingleTap: { r, c in session.toggleBlock(row: r, col: c) },
                  onDoubleTap: { r, c in session.placeCat(row: r, col: c) },
                  onPaint: { r, c in session.paintBlock(row: r, col: c) })
            .padding(8)
            .background(MeowTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    private func applyLabel(for hint: Hint) -> String {
        switch hint.kind {
        case .exclude, .testExclude: return "Apply"
        case .focus:                 return "Got it"
        }
    }

    private func hintPopover(_ hint: Hint) -> some View {
        VStack {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill").foregroundStyle(.orange).font(.title3)
                Text(hint.reason)
                    .font(.callout.weight(.medium)).foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color(white: 0.98), in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
            .padding(.horizontal, 18)
            .padding(.top, 96)
            Spacer()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder private var controls: some View {
        if let hint = session.activeHint {
            HStack(spacing: 12) {
                Button { session.dismissHint() } label: {
                    Text("Dismiss").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(MeowTheme.ink)

                Button {
                    hint.canApply ? session.applyHint() : session.dismissHint()
                } label: {
                    Text(applyLabel(for: hint)).bold().frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.orange)
            }
            .frame(maxWidth: 340)
        } else {
            HStack(spacing: 12) {
                Button { session.undo() } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(MeowTheme.ink)
                .disabled(!session.canUndo)

                if mode.hintsAllowed {
                    Button { session.hint() } label: {
                        Label("Hint", systemImage: "lightbulb.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(.yellow)
                    .disabled(session.isOver)
                }
            }
            .frame(maxWidth: 340)
        }
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
            Text("+\(earnedScore) points").font(.headline).foregroundStyle(.yellow)
            ShareLink(item: shareText) {
                Label("Share result", systemImage: "square.and.arrow.up")
                    .font(.subheadline.bold())
            }
            .tint(MeowTheme.ink)
        }
    }

    /// Spoiler-free brag text (never reveals cat positions).
    private var shareText: String {
        let stars = String(repeating: "⭐️", count: earnedStars) + String(repeating: "▫️", count: 3 - earnedStars)
        var header = "Meowdoku · \(mode.title)"
        if case .daily(let key) = mode.kind { header = "Meowdoku Daily \(key)" }
        return """
        \(header)
        \(mode.size)×\(mode.size) solved in \(timeString(session.elapsed)) 🐱
        \(stars)
        """
    }

    private var resultTitle: String {
        guard session.isWon else { return "Out of hearts" }
        return earnedStars == 3 ? "Flawless!" : "Purr-fect!"
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
            buttons.append(ResultButton(title: "Replay", style: .bordered, tint: MeowTheme.ink, action: onReplay))
        } else {
            buttons.append(ResultButton(
                title: session.isWon ? "Play again" : "Try again",
                style: .prominent, tint: session.isWon ? .green : .orange, action: onReplay))
        }
        buttons.append(ResultButton(title: "Back", style: .bordered, tint: MeowTheme.ink, action: onExit))
        return buttons
    }

    // MARK: Recording

    private func recordWin() {
        guard !recorded else { return }
        recorded = true
        earnedStars = LevelCatalog.stars(mistakes: session.mistakes, hintsUsed: session.hintsUsed)
        earnedScore = profile.awardScore(size: mode.size, stars: earnedStars,
                                          seconds: session.elapsed, heartsLeft: session.heartsRemaining)
        profile.recordGame(won: true)
        let gc = GameCenter.shared
        switch mode.kind {
        case .level(let i):
            profile.completeLevel(i, stars: earnedStars, time: session.elapsed)
            gc.submitTime(session.elapsed, leaderboardID: GameCenter.Leaderboard.time(size: mode.size))
            if i >= 50 { gc.report(GameCenter.Achievement.level50) }
        case .daily(let key):
            profile.recordDaily(key: key, solved: true)
            Reminders.refresh()   // move the nudge to tomorrow now that today's done
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
        Task { await profile.sync() }
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

/// Which rule a `MiniRuleGrid` glyph illustrates.
enum RuleKind { case color, line, touch }

/// A tiny 3×3 glyph for the rule cards: distinct colored cells (per-color), a
/// tinted cross (per row & column), or an isolated center cell (no touching).
struct MiniRuleGrid: View {
    let kind: RuleKind
    private let side: CGFloat = 8

    var body: some View {
        VStack(spacing: 1.5) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 1.5) {
                    ForEach(0..<3, id: \.self) { c in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(fill(r, c))
                            .frame(width: side, height: side)
                            .overlay {
                                if r == 1 && c == 1 {
                                    Circle().fill(Color(red: 0.22, green: 0.22, blue: 0.26))
                                        .frame(width: side * 0.5, height: side * 0.5)
                                }
                            }
                    }
                }
            }
        }
    }

    private func fill(_ r: Int, _ c: Int) -> Color {
        let dim = Color.gray.opacity(0.18)
        switch kind {
        case .color:
            let cols = [Color(red: 0.97, green: 0.71, blue: 0.72),
                        Color(red: 0.66, green: 0.83, blue: 0.95),
                        Color(red: 0.80, green: 0.86, blue: 0.66)]
            return cols[r % cols.count].opacity(0.9)
        case .line:
            return (r == 1 || c == 1) ? Color(red: 0.80, green: 0.73, blue: 0.96) : dim
        case .touch:
            return (r == 1 && c == 1) ? Color(red: 0.66, green: 0.83, blue: 0.95) : dim
        }
    }
}

/// Three-star rating row.
struct StarRow: View {
    let stars: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .foregroundStyle(i < stars ? .yellow : MeowTheme.ink.opacity(0.3))
                    .font(.title3)
            }
        }
    }
}
