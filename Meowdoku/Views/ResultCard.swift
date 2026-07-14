import SwiftUI

/// A celebratory / commiserating overlay shown at the end of a game.
struct ResultCard: View {
    let won: Bool
    let title: String
    let subtitle: String
    var primaryTitle: String
    var primaryAction: () -> Void
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(won ? MeowTheme.winGlyph : MeowTheme.loseGlyph)
                    .font(.system(size: 68))
                Text(title)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Button(action: primaryAction) {
                        Text(primaryTitle).font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(won ? .green : .orange)

                    if let secondaryTitle, let secondaryAction {
                        Button(action: secondaryAction) {
                            Text(secondaryTitle).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 340)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(24)
        }
        .transition(.opacity)
    }
}
