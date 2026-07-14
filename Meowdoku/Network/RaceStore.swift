import SwiftUI

/// Drives an online race end to end: create/join → wait → countdown → play →
/// finish. Opponent state is refreshed by polling the match row; the outcome is
/// resolved atomically on the server (first to claim `winner` wins).
@MainActor
final class RaceStore: ObservableObject {

    enum Phase: Equatable {
        case lobby            // choosing create vs join
        case waitingForOpponent
        case countdown
        case playing
        case finished
    }

    @Published var phase: Phase = .lobby
    @Published var match: Match?
    @Published var session: GameSession?
    @Published var role: PlayerRole = .host
    @Published var myName: String = ""
    @Published var opponentName: String = ""
    @Published var opponentProgress: Int = 0
    @Published var opponentAlive: Bool = true
    @Published var countdownValue: Int = 3
    @Published var iWon: Bool? = nil
    @Published var endReason: String? = nil
    @Published var busy = false
    @Published var errorMessage: String?

    private var pollTask: Task<Void, Never>?
    private var claimed = false

    var boardSize: Int { match?.size ?? 8 }

    // MARK: - Lobby actions

    func createMatch(name: String, size: Int) async {
        myName = name.isEmpty ? "Player 1" : name
        role = .host
        busy = true; errorMessage = nil
        do {
            let seed = Int64.random(in: Int64.min...Int64.max)
            let m = try await MeowAPI.createMatch(hostName: myName, size: size, seed: seed)
            match = m
            phase = .waitingForOpponent
            startLobbyPolling()
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    func joinMatch(name: String, code: String) async {
        myName = name.isEmpty ? "Player 2" : name
        role = .guest
        busy = true; errorMessage = nil
        do {
            let m = try await MeowAPI.joinMatch(code: code.uppercased(), guestName: myName)
            match = m
            opponentName = m.hostName
            beginCountdown()
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    /// Host waits here until a guest claims the open slot.
    private func startLobbyPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard let self else { return }
                guard let id = self.match?.id, self.phase == .waitingForOpponent else { return }
                if let fresh = try? await MeowAPI.fetchMatch(id: id),
                   fresh.statusValue == .playing, let guest = fresh.guestName {
                    self.match = fresh
                    self.opponentName = guest
                    self.beginCountdown()
                    return
                }
            }
        }
    }

    // MARK: - Countdown & play

    private func beginCountdown() {
        guard let m = match else { return }
        // Both players generate the *same* puzzle from the shared seed.
        let board = PuzzleGenerator.generate(seed: m.seedBits, size: m.size)
        session = GameSession(board: board, allowedMistakes: 1)
        opponentProgress = 0
        opponentAlive = true
        iWon = nil
        endReason = nil
        claimed = false
        countdownValue = 3
        phase = .countdown

        pollTask?.cancel()
        pollTask = Task { [weak self] in
            for n in stride(from: 3, through: 1, by: -1) {
                await MainActor.run { self?.countdownValue = n }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            await MainActor.run { self?.startPlaying() }
        }
    }

    private func startPlaying() {
        phase = .playing
        startMatchPolling()
    }

    /// Handle a board tap during a race.
    func tap(row: Int, col: Int, noteMode: Bool) {
        guard phase == .playing, let session, !session.isOver else { return }
        if noteMode {
            session.toggleBlock(row: row, col: col)
            return
        }
        switch session.placeCat(row: row, col: col) {
        case .placedCorrect:
            pushProgress()
            if session.isWon { Task { await declareWin() } }
        case .removed:
            pushProgress()
        case .mistake:
            Task { await declareLoss() }
        case .ignored:
            break
        }
    }

    private func pushProgress() {
        guard let id = match?.id, let session else { return }
        let p = session.progress
        Task { try? await MeowAPI.updateProgress(id: id, role: role, progress: p) }
    }

    private func declareWin() async {
        guard let id = match?.id, !claimed else { return }
        claimed = true
        let won = (try? await MeowAPI.claimResult(
            id: id, winnerName: myName, reason: "solved", aliveField: nil, alive: true
        )) ?? false
        finish(iWon: won, reason: won ? "solved" : "opponent_solved")
        if !won { session?.forceLose() }
    }

    private func declareLoss() async {
        guard let id = match?.id, !claimed else { return }
        claimed = true
        // My mistake hands the win to my opponent.
        _ = try? await MeowAPI.claimResult(
            id: id, winnerName: opponentName, reason: "mistake",
            aliveField: role, alive: false
        )
        finish(iWon: false, reason: "mistake")
    }

    /// Poll the opponent's progress and detect a server-side finish.
    private func startMatchPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let stillPlaying = await MainActor.run { self.phase == .playing }
                if !stillPlaying { return }
                guard let id = await MainActor.run(body: { self.match?.id }) else { return }

                if let fresh = try? await MeowAPI.fetchMatch(id: id) {
                    await MainActor.run { self.absorb(fresh) }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func absorb(_ fresh: Match) {
        match = fresh
        opponentProgress = role == .host ? fresh.guestProgress : fresh.hostProgress
        opponentAlive = role == .host ? fresh.guestAlive : fresh.hostAlive

        guard phase == .playing, fresh.statusValue == .finished, !claimed else { return }
        // Opponent ended the game first.
        claimed = true
        let didWin = (fresh.winner == myName)
        if !didWin { session?.forceLose() }
        finish(iWon: didWin, reason: didWin ? "opponent_mistake" : (fresh.endReason ?? "lost"))
    }

    private func finish(iWon: Bool, reason: String) {
        self.iWon = iWon
        self.endReason = reason
        phase = .finished
        pollTask?.cancel()
    }

    // MARK: - Teardown

    func leave() {
        pollTask?.cancel()
        pollTask = nil
        // Best-effort forfeit if we bail mid-game.
        if phase == .playing, let id = match?.id, !claimed {
            claimed = true
            let opp = opponentName
            let r = role
            Task { _ = try? await MeowAPI.claimResult(id: id, winnerName: opp, reason: "forfeit", aliveField: r, alive: false) }
        }
        reset()
    }

    func reset() {
        phase = .lobby
        match = nil
        session = nil
        opponentProgress = 0
        opponentAlive = true
        iWon = nil
        endReason = nil
        claimed = false
        errorMessage = nil
    }
}
