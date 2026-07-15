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
                    section("Appearance") {
                        Picker("Appearance", selection: Binding(
                            get: { profile.appearance }, set: { profile.appearance = $0 })) {
                            ForEach(Appearance.allCases) { a in Text(a.title).tag(a) }
                        }
                        .pickerStyle(.segmented)
                    }

                    section("Cat piece") {
                        LazyVGrid(columns: styleColumns, spacing: 10) {
                            ForEach(CatStyles.all) { style in
                                Button {
                                    profile.catStyleID = style.id
                                    Haptics.light()
                                } label: {
                                    CatFace(style: style)
                                        .frame(width: 40, height: 40)
                                        .frame(width: 54, height: 54)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(profile.catStyleID == style.id ? Color.pink.opacity(0.5) : MeowTheme.ink.opacity(0.12))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(profile.catStyleID == style.id ? Color.pink : .clear, lineWidth: 2)
                                        )
                                }
                            }
                        }
                    }

                    section("Square colors") {
                        VStack(spacing: 10) {
                            ForEach(MeowPalettes.all) { p in
                                Button {
                                    profile.paletteID = p.id
                                    Haptics.light()
                                } label: {
                                    HStack(spacing: 10) {
                                        HStack(spacing: 3) {
                                            ForEach(0..<p.colors.count, id: \.self) { i in
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(p.colors[i])
                                                    .frame(width: 18, height: 24)
                                            }
                                        }
                                        Text(p.name).font(.subheadline.bold()).foregroundStyle(MeowTheme.ink)
                                        Spacer()
                                        if profile.paletteID == p.id {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.pink)
                                        }
                                    }
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(profile.paletteID == p.id ? Color.pink.opacity(0.18) : .clear))
                                }
                            }
                        }
                    }

                    section("Assist") {
                        toggle("Auto-mark X's", systemImage: "xmark.square.fill", isOn: Binding(
                            get: { profile.autoMarkOn }, set: { profile.autoMarkOn = $0 }))
                        Text("When you place a cat, automatically X out the cells it rules out. Solo modes only.")
                            .font(.caption).foregroundStyle(MeowTheme.ink.opacity(0.55))
                    }

                    section("Feedback") {
                        toggle("Haptics", systemImage: "hand.tap.fill", isOn: Binding(
                            get: { profile.hapticsOn }, set: { profile.hapticsOn = $0 }))
                        toggle("Sound", systemImage: "speaker.wave.2.fill", isOn: Binding(
                            get: { profile.soundOn }, set: { profile.soundOn = $0 }))
                    }

                    section("Notifications") {
                        toggle("Daily reminder", systemImage: "bell.fill", isOn: Binding(
                            get: { profile.remindersOn },
                            set: { on in
                                if on { Task { await Reminders.enable() } }
                                else { Reminders.disable() }
                            }))
                        Text("A gentle nudge at 7pm when today's puzzle is still unsolved — never when you've already played.")
                            .font(.caption).foregroundStyle(MeowTheme.ink.opacity(0.55))
                    }

                    section("Stats") {
                        statRow("Games played", "\(profile.totalGames)")
                        statRow("Wins", "\(profile.totalWins)")
                        statRow("Levels completed", "\(profile.levelsCompleted)/\(LevelCatalog.totalLevels)")
                        statRow("Total stars", "\(profile.totalStars)")
                        statRow("Daily streak", "🔥 \(profile.dailyStreak) (best \(profile.dailyBestStreak))")
                        Button { showGameCenter = true } label: {
                            Label("Game Center", systemImage: "trophy.fill")
                                .foregroundStyle(MeowTheme.ink).frame(maxWidth: .infinity, alignment: .leading)
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
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(MeowTheme.ink.opacity(0.6))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MeowTheme.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private func toggle(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: systemImage).foregroundStyle(MeowTheme.ink)
        }
        .tint(.pink)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(MeowTheme.ink.opacity(0.8))
            Spacer()
            Text(value).foregroundStyle(MeowTheme.ink).bold()
        }
        .font(.subheadline)
    }
}
