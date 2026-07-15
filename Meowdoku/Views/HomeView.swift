import SwiftUI

struct HomeView: View {
    @ObservedObject private var profile = PlayerProfile.shared
    @State private var difficulty: Difficulty = .normal
    @State private var route: Route?
    @State private var showTutorial = false

    enum Route: Hashable, Identifiable {
        case daily, levels, race, settings
        case timeAttack(size: Int, seed: UInt64)
        case freeplay(size: Int, seed: UInt64)
        var id: String {
            switch self {
            case .daily: return "daily"
            case .levels: return "levels"
            case .race: return "race"
            case .settings: return "settings"
            case .timeAttack(let s, let seed): return "ta-\(s)-\(seed)"
            case .freeplay(let s, let seed): return "fp-\(s)-\(seed)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MeowTheme.backdrop.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        title
                        dailyCard
                        levelsCard
                        raceCard
                        difficultyStrip
                        HStack(spacing: 12) {
                            smallCard(icon: "pawprint.fill", title: "Free play", tint: .indigo) {
                                route = .freeplay(size: difficulty.size, seed: .random(in: 0...UInt64.max))
                            }
                            smallCard(icon: "clock.fill", title: "Time Attack", tint: .teal) {
                                route = .timeAttack(size: difficulty.size, seed: .random(in: 0...UInt64.max))
                            }
                        }
                    }
                    .padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { route = .settings } label: { Image(systemName: "gearshape.fill") }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .tint(.white)
            .navigationDestination(item: $route) { route in destination(route) }
        }
        .tint(.white)
        .fullScreenCover(isPresented: $showTutorial) { TutorialView() }
        .onAppear { if !profile.tutorialSeen { showTutorial = true } }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .daily:                       GameplayView(mode: .daily(key: DailyPuzzle.dateKey()))
        case .levels:                      LevelSelectView()
        case .race:                        RaceContainerView()
        case .settings:                    SettingsView()
        case .timeAttack(let s, let seed): GameplayView(mode: .timeAttack(size: s, seed: seed))
        case .freeplay(let s, let seed):   GameplayView(mode: .freeplay(difficulty: Difficulty(rawValue: s) ?? .normal, seed: seed))
        }
    }

    // MARK: Pieces

    private var title: some View {
        VStack(spacing: 8) {
            Text("🐱").font(.system(size: 72))
            Text("Meowdoku")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("One cat per row, column & color. No two cats touch.")
                .font(.footnote).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button { showTutorial = true } label: {
                Label("How to play", systemImage: "questionmark.circle")
                    .font(.footnote.bold())
            }
            .tint(.white).padding(.top, 2)
        }
        .padding(.top, 8)
    }

    private var dailyCard: some View {
        Button { route = .daily } label: {
            bigCard(icon: profile.todaySolved ? "checkmark.seal.fill" : "calendar",
                    title: "Daily Puzzle",
                    subtitle: profile.todaySolved
                        ? "Done today · 🔥 \(profile.dailyStreak)-day streak"
                        : "🔥 \(profile.dailyStreak)-day streak · play today's board",
                    tint: .pink)
        }
    }

    private var levelsCard: some View {
        Button { route = .levels } label: {
            bigCard(icon: "map.fill",
                    title: "Levels",
                    subtitle: "\(profile.levelsCompleted)/\(LevelCatalog.totalLevels) · next: Level \(profile.highestUnlocked)",
                    tint: .purple)
        }
    }

    private var raceCard: some View {
        Button { route = .race } label: {
            bigCard(icon: "bolt.fill", title: "Race Audie",
                    subtitle: "Live head-to-head · one mistake, no hints", tint: .orange)
        }
    }

    private var difficultyStrip: some View {
        Picker("Difficulty", selection: $difficulty) {
            ForEach(Difficulty.allCases) { d in Text("\(d.title) · \(d.subtitle)").tag(d) }
        }
        .pickerStyle(.segmented)
    }

    private func bigCard(icon: String, title: String, subtitle: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).opacity(0.85)
            }
            Spacer()
            Image(systemName: "chevron.right").opacity(0.5)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
    }

    private func smallCard(icon: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundStyle(tint)
                Text(title).font(.subheadline.bold())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
        }
    }
}
