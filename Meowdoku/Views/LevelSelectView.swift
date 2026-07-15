import SwiftUI

/// The campaign map: a scrollable grid of levels showing stars earned, the next
/// unlocked level, and locks beyond it.
struct LevelSelectView: View {
    @ObservedObject private var profile = PlayerProfile.shared
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ZStack {
            MeowTheme.backdrop.ignoresSafeArea()
            ScrollView {
                header
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(1...LevelCatalog.totalLevels, id: \.self) { level in
                        levelCell(level)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Levels")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack {
            Label("\(profile.totalStars) stars", systemImage: "star.fill").foregroundStyle(.yellow)
            Spacer()
            Text("\(profile.levelsCompleted)/\(LevelCatalog.totalLevels) done")
                .foregroundStyle(MeowTheme.ink.opacity(0.8))
        }
        .font(.subheadline.bold())
        .padding(.horizontal).padding(.top, 8)
    }

    @ViewBuilder
    private func levelCell(_ level: Int) -> some View {
        let unlocked = level <= profile.highestUnlocked
        let stars = profile.stars(forLevel: level)
        let completed = profile.isCompleted(level: level)

        Group {
            if unlocked {
                NavigationLink { GameplayView(mode: .level(level)) } label: { tile(level, stars: stars, completed: completed, unlocked: true) }
            } else {
                tile(level, stars: stars, completed: false, unlocked: false)
            }
        }
    }

    private func tile(_ level: Int, stars: Int, completed: Bool, unlocked: Bool) -> some View {
        VStack(spacing: 4) {
            if unlocked {
                Text("\(level)").font(.title3.bold()).foregroundStyle(MeowTheme.ink)
            } else {
                Image(systemName: "lock.fill").font(.body).foregroundStyle(MeowTheme.ink.opacity(0.5))
            }
            HStack(spacing: 1) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < stars ? "star.fill" : "star")
                        .font(.system(size: 8))
                        .foregroundStyle(i < stars ? .yellow : MeowTheme.ink.opacity(0.25))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(completed ? Color.pink.opacity(0.35)
                      : unlocked ? MeowTheme.ink.opacity(0.14) : MeowTheme.ink.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(level == profile.highestUnlocked && !completed ? Color.pink : .clear, lineWidth: 2)
        )
    }
}
