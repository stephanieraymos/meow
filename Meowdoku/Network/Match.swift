import Foundation

/// A race between two players. Both regenerate the identical puzzle locally from
/// `seed` + `size`; the server row only tracks who's ahead and who won.
struct Match: Codable, Identifiable, Equatable {
    var id: String
    var code: String
    var size: Int
    var seed: Int64
    var status: String            // waiting | playing | finished
    var hostName: String
    var guestName: String?
    var winner: String?
    var endReason: String?        // solved | mistake | forfeit
    var hostProgress: Int
    var guestProgress: Int
    var hostAlive: Bool
    var guestAlive: Bool
    var hostAvatar: String?
    var guestAvatar: String?
    var hostId: String?
    var guestId: String?
    var rematchOffer: String?
    var rematchRound: Int

    enum Status: String { case waiting, playing, finished }
    var statusValue: Status { Status(rawValue: status) ?? .waiting }

    var seedBits: UInt64 { UInt64(bitPattern: seed) }

    /// Deterministic per-round seed so a rematch reset never diverges.
    func seedForRound(_ round: Int) -> UInt64 {
        var s = seedBits
        if round > 0 {
            s = (s ^ (UInt64(round) &* 0x9E3779B97F4A7C15))
            s = (s ^ (s >> 30)) &* 0xBF58476D1CE4E5B9
            s ^= s >> 27
        }
        return s | 1
    }
    var currentSeed: UInt64 { seedForRound(rematchRound) }
}

/// Which side of a match the local player is on.
enum PlayerRole { case host, guest }

/// A pickable racer (from the anon-readable `meow_players` table).
struct MeowPlayer: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var avatarUrl: String?
}
