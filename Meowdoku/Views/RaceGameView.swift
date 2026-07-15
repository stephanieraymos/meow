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
                              style: PlayerProfile.shared.catStyle,
                              onSingleTap: { r, c in store.tap(row: r, col: c, noteMode: true) },
                              onDoubleTap: { r, c in store.tap(row: r, col: c, noteMode: false) },
                              onPaint: { r, c in store.paint(row: r, col: c) })
                        .padding(.horizontal, 8)
                        .disabled(store.phase != .playing)
                    Text("Double-tap to place a cat · tap or drag to mark X")
                        .font(.caption2).foregroundStyle(.white.opacity(0.55))
                }
                .padding()
            } else {
                ProgressView().tint(.white)
            }

            if store.phase == .countdown { countdownOverlay }
            if store.phase == .finished { resultOverlay }
        }
    }

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
            title: won ? "You win! 🏆" : "\(displayOpp) wins",
            subtitle: subtitle(won: won),
            accessory: rematchStatus,
            buttons: rematchButtons
        )
    }

    private var rematchStatus: AnyView? {
        if store.rematchOffered {
            return AnyView(Label("Waiting for \(displayOpp) to accept…", systemImage: "hourglass")
                .font(.footnote).foregroundStyle(.white.opacity(0.85)))
        }
        if store.opponentWantsRematch {
            return AnyView(Label("\(displayOpp) wants a rematch!", systemImage: "flame.fill")
                .font(.footnote.bold()).foregroundStyle(.pink))
        }
        return nil
    }

    private var rematchButtons: [ResultButton] {
        var buttons: [ResultButton] = []
        if !store.rematchOffered {
            let title = store.opponentWantsRematch ? "Accept rematch" : "Rematch"
            buttons.append(ResultButton(title: title, style: .prominent, tint: .pink) { store.rematch() })
        }
        buttons.append(ResultButton(title: "Back to lobby", style: .bordered, tint: .white) { store.reset() })
        return buttons
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
