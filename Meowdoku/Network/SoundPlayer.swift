import AVFoundation

/// Plays short, synthesized game sounds. Gated by the player's Sound setting and
/// routed through the `.ambient` category so it respects the silent switch and
/// mixes politely with other audio.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    enum Sound: String, CaseIterable {
        case pop, correct, tick, mistake, win, lose
    }

    private var players: [Sound: AVAudioPlayer] = [:]
    private var configured = false

    func preload() {
        guard !configured else { return }
        configured = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for sound in Sound.allCases {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[sound] = player
        }
    }

    func play(_ sound: Sound) {
        guard PlayerProfile.shared.soundOn else { return }
        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }
}
