import SwiftUI

/// The live race screen: your board, a live opponent progress bar, the pre-game
/// countdown, and the win/lose result.
struct RaceGameView: View {
    @ObservedObject var store: RaceStore

    var body: some View {
        ZStack {
            MeowTheme.backdrop.ignoresSafeArea()

            if let session = store.session {
                VStack(spacing: 14) {
                    scoreboard(session: session)
                    BoardView(session: session,
                              onTap: { r, c in store.tap(row: r, col: c, noteMode: noteMode) },
                              onLongPress: { r, c in store.tap(row: r, col: c, noteMode: true) })
                        .padding(.horizontal, 8)
                        .disabled(store.phase != .playing)
                    controls
                }
                .padding()
            } else {
                ProgressView().tint(.white)
            }

            if store.phase == .countdown { countdownOverlay }
            if store.phase == .finished { resultOverlay }
        }
    }

    @State private var noteMode = false

    // MARK: Scoreboard

    private func scoreboard(session: GameSession) -> some View {
        let n = store.boardSize
        return VStack(spacing: 10) {
            progressRow(name: store.myName.isEmpty ? "You" : store.myName,
                        value: session.progress, total: n, alive: !session.isLost, mine: true)
            progressRow(name: store.opponentName.isEmpty ? "Audie" : store.opponentName,
                        value: store.opponentProgress, total: n, alive: store.opponentAlive, mine: false)
        }
    }

    private func progressRow(name: String, value: Int, total: Int, alive: Bool, mine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.subheadline.bold()).foregroundStyle(.white)
                if !alive { Text("💥 out").font(.caption).foregroundStyle(.orange) }
                Spacer()
                Text("\(value)/\(total)").font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.9))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule()
                        .fill(mine ? Color.pink : Color.cyan)
                        .frame(width: geo.size.width * CGFloat(value) / CGFloat(max(total, 1)))
                        .animation(.easeOut(duration: 0.25), value: value)
                }
            }
            .frame(height: 10)
        }
    }

    private var controls: some View {
        Picker("", selection: $noteMode) {
            Label("Cat", systemImage: "cat.fill").tag(false)
            Label("Note", systemImage: "xmark.square").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
        .disabled(store.phase != .playing)
    }

    // MARK: Overlays

    private var countdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 8) {
                Text("Get ready…").font(.title3).foregroundStyle(.white.opacity(0.85))
                Text("\(store.countdownValue)")
                    .font(.system(size: 96, weight: .heavy))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: store.countdownValue)
            }
        }
    }

    private var resultOverlay: some View {
        let won = store.iWon == true
        return ResultCard(
            won: won,
            title: won ? "You win! 🏆" : "Audie wins",
            subtitle: subtitle(won: won),
            primaryTitle: "Back to lobby",
            primaryAction: { store.reset() }
        )
    }

    private func subtitle(won: Bool) -> String {
        switch store.endReason {
        case "solved":            return "You placed every cat first."
        case "opponent_solved":   return "\(displayOpp) solved it a whisker sooner."
        case "mistake":           return "One wrong cat ended your run."
        case "opponent_mistake":  return "\(displayOpp) placed a wrong cat — you take it!"
        case "forfeit":           return won ? "\(displayOpp) left the race." : "You left the race."
        default:                  return won ? "Nice race!" : "So close — rematch?"
        }
    }

    private var displayOpp: String { store.opponentName.isEmpty ? "Audie" : store.opponentName }
}

/// Owns the race lifecycle and swaps between lobby and live game by phase.
struct RaceContainerView: View {
    @StateObject private var store = RaceStore()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch store.phase {
            case .lobby, .waitingForOpponent:
                RaceLobbyView(store: store)
            case .countdown, .playing, .finished:
                RaceGameView(store: store)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Exit") { store.leave(); dismiss() }
            }
        }
        .onDisappear { store.leave() }
    }
}
