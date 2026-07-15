import SwiftUI

/// Drives an online race end to end: create/join → wait → countdown → play →
/// finish → (optional) rematch.
///
/// Live state arrives over a Supabase Realtime websocket (`MeowRealtime`), with a
/// slow REST poll as a safety net and automatic re-sync on reconnect. Every
/// update — from either transport — funnels through `ingest(_:)`. The winner is
/// resolved atomically on the server (first to claim `winner` wins).
@MainActor
final class RaceStore: ObservableObject {

    enum Phase: Equatable {
        case lobby
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
    @Published var myAvatar: String? = nil
    @Published var opponentAvatar: String? = nil
    @Published var myID: String? = nil
    @Published var opponentID: String? = nil
    @Published var rivalryMe: Int = 0
    @Published var rivalryOpp: Int = 0
    @Published var opponentProgress: Int = 0
    @Published var opponentAlive: Bool = true
    @Published var countdownValue: Int = 3
    @Published var iWon: Bool? = nil
    @Published var endReason: String? = nil
    @Published var busy = false
    @Published var errorMessage: String?
    @Published var rematchOffered = false
    @Published var opponentWantsRematch = false

    private let realtime = MeowRealtime()
    private var backupPoll: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var claimed = false
    private var currentRound = 0

    var boardSize: Int { match?.size ?? 8 }

    // MARK: - Lobby actions

    func createMatch(name: String, size: Int, avatar: String? = nil, playerId: String? = nil) async {
        myName = name.isEmpty ? "Player 1" : name
        myAvatar = avatar
        myID = playerId
        role = .host
        busy = true; errorMessage = nil
        do {
            let seed = Int64.random(in: Int64.min...Int64.max)
            match = try await MeowAPI.createMatch(hostName: myName, size: size, seed: seed, avatar: avatar, playerId: playerId)
            phase = .waitingForOpponent
            startSync()
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    func joinMatch(name: String, code: String, avatar: String? = nil, playerId: String? = nil) async {
        myName = name.isEmpty ? "Player 2" : name
        myAvatar = avatar
        myID = playerId
        role = .guest
        busy = true; errorMessage = nil
        do {
            let m = try await MeowAPI.joinMatch(code: code.uppercased(), guestName: myName, avatar: avatar, playerId: playerId)
            match = m
            opponentName = m.hostName
            opponentAvatar = m.hostAvatar
            opponentID = m.hostId
            startSync()
            beginCountdown()
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    // MARK: - Live sync (realtime + backup poll → ingest)

    private func startSync() {
        guard let id = match?.id else { return }
        realtime.start(
            matchId: id,
            onChange: { [weak self] fresh in self?.ingest(fresh) },
            onReconnect: { [weak self] in self?.refetch() })
        startBackupPoll()
    }

    private func refetch() {
        guard let id = match?.id else { return }
        Task { [weak self] in
            if let fresh = try? await MeowAPI.fetchMatch(id: id) {
                await MainActor.run { self?.ingest(fresh) }
            }
        }
    }

    /// Slow safety-net poll in case the websocket drops entirely.
    private func startBackupPoll() {
        backupPoll?.cancel()
        backupPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self else { return }
                let active = await MainActor.run { self.match != nil && self.phase != .lobby }
                if !active { return }
                guard let id = await MainActor.run(body: { self.match?.id }) else { return }
                if let fresh = try? await MeowAPI.fetchMatch(id: id) {
                    await MainActor.run { self.ingest(fresh) }
                }
            }
        }
    }

    /// Single entry point for every match update, regardless of transport.
    private func ingest(_ fresh: Match) {
        match = fresh
        opponentProgress = role == .host ? fresh.guestProgress : fresh.hostProgress
        opponentAlive = role == .host ? fresh.guestAlive : fresh.hostAlive

        opponentAvatar = role == .host ? fresh.guestAvatar : fresh.hostAvatar
        opponentID = role == .host ? fresh.guestId : fresh.hostId

        switch phase {
        case .waitingForOpponent:
            if fresh.statusValue == .playing, let guest = fresh.guestName {
                opponentName = guest
                opponentAvatar = fresh.guestAvatar
                opponentID = fresh.guestId
                beginCountdown()
            }

        case .countdown, .playing:
            if fresh.statusValue == .finished, !claimed {
                claimed = true
                let didWin = (fresh.winner == myName)
                if !didWin { session?.forceLose() }
                // This branch only fires on the *opponent's* terminal action, so
                // from our side: they either solved first (we lose) or slipped up
                // / forfeited (we win).
                let reason: String
                if didWin {
                    reason = fresh.endReason == "forfeit" ? "forfeit" : "opponent_mistake"
                } else {
                    reason = "opponent_solved"
                }
                finish(iWon: didWin, reason: reason)
            }

        case .finished:
            if fresh.statusValue == .playing, fresh.rematchRound > currentRound {
                beginCountdown()   // a rematch round started
                return
            }
            opponentWantsRematch = (fresh.rematchOffer == opponentName && !opponentName.isEmpty)
            if opponentWantsRematch, rematchOffered, let id = match?.id, myName < opponentName {
                Task { [weak self] in await self?.applyRematch(round: fresh.rematchRound + 1, id: id) }
            }

        case .lobby:
            break
        }
    }

    // MARK: - Countdown & play

    private func beginCountdown() {
        guard let m = match else { return }
        currentRound = m.rematchRound
        // Both players generate the *same* puzzle from the shared per-round seed.
        let board = PuzzleGenerator.generate(seed: m.currentSeed, size: m.size)
        // Never auto-mark X's in a race — it would hand an unfair time advantage
        // to whoever has the solo setting on. Everyone marks by hand here.
        session = GameSession(board: board, allowedMistakes: 1, autoMark: false)
        opponentProgress = 0
        opponentAlive = true
        iWon = nil
        endReason = nil
        claimed = false
        rematchOffered = false
        opponentWantsRematch = false
        countdownValue = 3
        phase = .countdown

        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            for n in stride(from: 3, through: 1, by: -1) {
                await MainActor.run { self?.countdownValue = n }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            await MainActor.run { self?.startPlaying() }
        }
    }

    private func startPlaying() { phase = .playing }

    /// Handle a board tap during a race.
    func tap(row: Int, col: Int, noteMode: Bool) {
        guard phase == .playing, let session, !session.isOver else { return }
        if noteMode { session.toggleBlock(row: row, col: col); return }
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

    /// Paint an X note while dragging (never affects win/loss).
    func paint(row: Int, col: Int) {
        guard phase == .playing, let session, !session.isOver else { return }
        session.paintBlock(row: row, col: col)
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
            id: id, winnerName: myName, reason: "solved", aliveField: nil, alive: true)) ?? false
        finish(iWon: won, reason: won ? "solved" : "opponent_solved")
        if !won { session?.forceLose() }
    }

    private func declareLoss() async {
        guard let id = match?.id, !claimed else { return }
        claimed = true
        _ = try? await MeowAPI.claimResult(
            id: id, winnerName: opponentName, reason: "mistake", aliveField: role, alive: false)
        finish(iWon: false, reason: "mistake")
    }

    private func finish(iWon: Bool, reason: String) {
        countdownTask?.cancel()
        self.iWon = iWon
        self.endReason = reason
        phase = .finished
        // Realtime + backup poll stay live to catch a rematch.

        // Refresh the head-to-head record (the server trigger has just logged
        // this result). Small delay so it's committed before we read.
        if let a = myID, let b = opponentID {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 700_000_000)
                if let r = try? await MeowAPI.fetchRivalry(a: a, b: b) {
                    await MainActor.run { self?.rivalryMe = r.aWins; self?.rivalryOpp = r.bWins }
                }
            }
        }
    }

    // MARK: - Rematch

    /// Offer a rematch, or accept the opponent's standing offer.
    func rematch() {
        guard let id = match?.id else { return }
        Task {
            guard let fresh = try? await MeowAPI.fetchMatch(id: id) else { return }
            if fresh.rematchOffer == opponentName && !opponentName.isEmpty {
                await applyRematch(round: fresh.rematchRound + 1, id: id)
            } else {
                try? await MeowAPI.offerRematch(id: id, name: myName)
                rematchOffered = true
            }
        }
    }

    private func applyRematch(round: Int, id: String) async {
        if let started = try? await MeowAPI.applyRematch(id: id, newRound: round) {
            match = started
            beginCountdown()
        }
    }

    // MARK: - Teardown

    func leave() {
        // Best-effort forfeit if we bail mid-game.
        if phase == .playing, let id = match?.id, !claimed {
            claimed = true
            let opp = opponentName, r = role
            Task { _ = try? await MeowAPI.claimResult(id: id, winnerName: opp, reason: "forfeit", aliveField: r, alive: false) }
        }
        reset()
    }

    func reset() {
        realtime.stop()
        backupPoll?.cancel(); backupPoll = nil
        countdownTask?.cancel(); countdownTask = nil
        phase = .lobby
        match = nil
        session = nil
        opponentName = ""
        opponentAvatar = nil
        opponentID = nil
        rivalryMe = 0
        rivalryOpp = 0
        opponentProgress = 0
        opponentAlive = true
        iWon = nil
        endReason = nil
        claimed = false
        errorMessage = nil
        rematchOffered = false
        opponentWantsRematch = false
        currentRound = 0
    }
}
