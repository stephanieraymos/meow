import SwiftUI

struct HomeView: View {
    @State private var soloDifficulty: Difficulty = .normal

    var body: some View {
        NavigationStack {
            ZStack {
                MeowTheme.backdrop.ignoresSafeArea()
                VStack(spacing: 28) {
                    Spacer()
                    VStack(spacing: 10) {
                        Text("🐱")
                            .font(.system(size: 84))
                        Text("Meowdoku")
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Place a cat in every row, column and color —\nno two cats may touch. No hints. No mistakes.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }

                    Spacer()

                    VStack(spacing: 16) {
                        NavigationLink {
                            RaceContainerView()
                        } label: {
                            menuLabel(icon: "bolt.fill", title: "Race Audie", subtitle: "Live head-to-head")
                        }
                        .tint(.pink)

                        VStack(spacing: 10) {
                            Picker("Difficulty", selection: $soloDifficulty) {
                                ForEach(Difficulty.allCases) { d in
                                    Text(d.title).tag(d)
                                }
                            }
                            .pickerStyle(.segmented)

                            NavigationLink {
                                SoloGameView(difficulty: soloDifficulty)
                            } label: {
                                menuLabel(icon: "pawprint.fill", title: "Play solo",
                                          subtitle: "Practice · \(soloDifficulty.subtitle)")
                            }
                            .tint(.indigo)
                        }
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .tint(.white)
    }

    private func menuLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).opacity(0.85)
            }
            Spacer()
            Image(systemName: "chevron.right").opacity(0.6)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
    }
}
