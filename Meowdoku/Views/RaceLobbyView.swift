import SwiftUI

/// Create or join a race. Once a match is created the host waits here on a shared
/// code until the guest joins.
struct RaceLobbyView: View {
    @ObservedObject var store: RaceStore
    var initialCode: String? = nil
    @AppStorage("meow_player_name") private var playerName: String = ""
    @AppStorage("meow_player_id") private var selectedID: String = ""
    @State private var players: [MeowPlayer] = []
    @State private var joinCode = ""
    @State private var difficulty: Difficulty = .normal
    @State private var autoJoined = false
    @FocusState private var focused: Bool

    private var selectedAvatar: String? {
        players.first { $0.id == selectedID }?.avatarUrl
    }

    var body: some View {
        ZStack {
            MeowTheme.backdrop.ignoresSafeArea()
            if store.phase == .waitingForOpponent {
                waiting
            } else {
                form
            }
        }
        .task {
            if players.isEmpty { players = (try? await MeowAPI.fetchPlayers()) ?? [] }
            // Arrived via an invite link: pre-fill the code and, if we already
            // know who this player is, join straight away.
            if let code = initialCode, !code.isEmpty, joinCode.isEmpty {
                joinCode = code
                if !autoJoined, !playerName.isEmpty {
                    autoJoined = true
                    await store.joinMatch(name: playerName, code: code, avatar: selectedAvatar)
                }
            }
        }
    }

    // MARK: Create / Join form

    private var form: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text("🐈‍⬛ 🆚 🐈")
                        .font(.system(size: 40))
                    Text("Race Audie")
                        .font(.largeTitle.bold()).foregroundStyle(MeowTheme.ink)
                    Text("Same puzzle, two boards. First to place every cat wins.\nOne wrong cat and you're out.")
                        .font(.callout).foregroundStyle(MeowTheme.ink.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                playerPicker

                field("Your name") {
                    TextField("e.g. Stephanie", text: $playerName)
                        .textInputAutocapitalization(.words)
                        .focused($focused)
                        .onChange(of: playerName) { _, _ in
                            // Typing a custom name clears the avatar selection.
                            if selectedAvatar != nil, players.first(where: { $0.id == selectedID })?.name != playerName {
                                selectedID = ""
                            }
                        }
                }

                // Create
                card {
                    Text("Start a new race").font(.headline).foregroundStyle(MeowTheme.ink)
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(Difficulty.allCases) { d in
                            Text("\(d.title) · \(d.subtitle)").tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                    Button {
                        Task { await store.createMatch(name: playerName, size: difficulty.size, avatar: selectedAvatar) }
                    } label: {
                        HStack {
                            if store.busy { ProgressView().tint(MeowTheme.ink) }
                            Text("Create game").bold()
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.pink)
                    .disabled(store.busy)
                }

                // Join
                card {
                    Text("Join with a code").font(.headline).foregroundStyle(MeowTheme.ink)
                    TextField("CODE", text: $joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title2.monospaced())
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .background(MeowTheme.ink.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                        .onChange(of: joinCode) { _, v in joinCode = String(v.uppercased().prefix(6)) }
                    Button {
                        Task { await store.joinMatch(name: playerName, code: joinCode, avatar: selectedAvatar) }
                    } label: {
                        Text("Join game").bold().frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.blue)
                    .disabled(store.busy || joinCode.count < 3)
                }

                if let err = store.errorMessage {
                    Text(err).font(.footnote).foregroundStyle(.yellow)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var playerPicker: some View {
        if !players.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Who's playing?").font(.subheadline).foregroundStyle(MeowTheme.ink.opacity(0.8))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(players) { p in
                            Button {
                                selectedID = p.id
                                playerName = p.name.split(separator: " ").first.map(String.init) ?? p.name
                                Haptics.light()
                            } label: {
                                VStack(spacing: 4) {
                                    CachedAvatar(urlString: p.avatarUrl, name: p.name, size: 58)
                                        .overlay(Circle().stroke(.pink, lineWidth: selectedID == p.id ? 3 : 0))
                                    Text(p.name.split(separator: " ").first.map(String.init) ?? p.name)
                                        .font(.caption).foregroundStyle(MeowTheme.ink.opacity(0.85))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    // MARK: Waiting for opponent

    private var waiting: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Share this code with Audie")
                .font(.headline).foregroundStyle(MeowTheme.ink.opacity(0.85))
            Text(store.match?.code ?? "…")
                .font(.system(size: 64, weight: .heavy, design: .monospaced))
                .foregroundStyle(MeowTheme.ink)
                .tracking(6)
            if let code = store.match?.code {
                ShareLink(item: "Race me in Meowdoku! 🐱 Tap to join: meowdoku://race/\(code)  (or enter code \(code))") {
                    Label("Send invite", systemImage: "square.and.arrow.up")
                }.tint(.pink)
            }
            ProgressView("Waiting for Audie to join…")
                .tint(MeowTheme.ink).foregroundStyle(MeowTheme.ink).padding(.top, 8)
            Spacer()
            Button("Cancel", role: .destructive) { store.leave() }
                .buttonStyle(.bordered).tint(MeowTheme.ink)
        }
        .padding()
    }

    // MARK: Bits

    @ViewBuilder private func field(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline).foregroundStyle(MeowTheme.ink.opacity(0.8))
            content()
                .textFieldStyle(.plain)
                .padding(12)
                .background(MeowTheme.ink.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(MeowTheme.ink)
        }
    }

    @ViewBuilder private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 12, content: content)
            .padding(16)
            .background(MeowTheme.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}
