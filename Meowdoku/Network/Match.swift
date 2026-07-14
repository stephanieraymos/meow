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

    enum Status: String { case waiting, playing, finished }
    var statusValue: Status { Status(rawValue: status) ?? .waiting }

    var seedBits: UInt64 { UInt64(bitPattern: seed) }
}

/// Which side of a match the local player is on.
enum PlayerRole { case host, guest }
