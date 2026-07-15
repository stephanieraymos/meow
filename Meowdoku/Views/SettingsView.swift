import SwiftUI

/// Cat piece style, feedback toggles, and lifetime stats.
struct SettingsView: View {
    @ObservedObject private var profile = PlayerProfile.shared
    @State private var showGameCenter = false
    private let styleColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        ZStack {
            MeowTheme.backdrop.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Cat piece") {
                        LazyVGrid(columns: styleColumns, spacing: 10) {
                            ForEach(CatStyles.all) { style in
                                Button {
                                    profile.catStyleID = style.id
                                    Haptics.light()
                                } label: {
                                    Text(style.glyph)
                                        .font(.system(size: 34))
                                        .frame(width: 54, height: 54)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(profile.catStyleID == style.id ? Color.pink.opacity(0.5) : Color.white.opacity(0.12))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(profile.catStyleID == style.id ? Color.pink : .clear, lineWidth: 2)
                                        )
                                }
                            }
                        }
                    }

                    section("Assist") {
                        toggle("Auto-mark X's", systemImage: "xmark.square.fill", isOn: Binding(
                            get: { profile.autoMarkOn }, set: { profile.autoMarkOn = $0 }))
                        Text("When you place a cat, automatically X out the cells it rules out. Solo modes only.")
                            .font(.caption).foregroundStyle(.white.opacity(0.55))
                    }

                    section("Feedback") {
                        toggle("Haptics", systemImage: "hand.tap.fill", isOn: Binding(
                            get: { profile.hapticsOn }, set: { profile.hapticsOn = $0 }))
                        toggle("Sound", systemImage: "speaker.wave.2.fill", isOn: Binding(
                            get: { profile.soundOn }, set: { profile.soundOn = $0 }))
                    }

                    section("Stats") {
                        statRow("Games played", "\(profile.totalGames)")
                        statRow("Wins", "\(profile.totalWins)")
                        statRow("Levels completed", "\(profile.levelsCompleted)/\(LevelCatalog.totalLevels)")
                        statRow("Total stars", "\(profile.totalStars)")
                        statRow("Daily streak", "🔥 \(profile.dailyStreak) (best \(profile.dailyBestStreak))")
                        Button { showGameCenter = true } label: {
                            Label("Game Center", systemImage: "trophy.fill")
                                .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGameCenter) { GameCenterDashboard().ignoresSafeArea() }
    }

    @ViewBuilder private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(.white.opacity(0.6))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private func toggle(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: systemImage).foregroundStyle(.white)
        }
        .tint(.pink)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(value).foregroundStyle(.white).bold()
        }
        .font(.subheadline)
    }
}
