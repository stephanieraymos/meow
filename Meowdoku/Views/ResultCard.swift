import SwiftUI

struct ResultButton: Identifiable {
    enum Style { case prominent, bordered }
    let id = UUID()
    let title: String
    let style: Style
    let tint: Color
    let action: () -> Void
}

/// A celebratory / commiserating overlay shown at the end of a game.
struct ResultCard: View {
    let won: Bool
    let title: String
    let subtitle: String
    var accessory: AnyView? = nil
    let buttons: [ResultButton]

    @State private var bounce = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            if won { ConfettiView().ignoresSafeArea() }
            VStack(spacing: 16) {
                Group {
                    if won {
                        CelebrationCat(style: PlayerProfile.shared.catStyle)
                            .frame(width: 128, height: 128)
                    } else {
                        CommiserationCat(style: PlayerProfile.shared.catStyle)
                            .frame(width: 112, height: 112)
                    }
                }

                Text(title).font(.title.bold()).foregroundStyle(.white)
                Text(subtitle)
                    .font(.callout).foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                if let accessory { accessory }

                VStack(spacing: 10) {
                    ForEach(buttons) { b in
                        Button(action: b.action) {
                            Text(b.title).font(.headline).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(b.style == .prominent ? b.tint : Color.white.opacity(0.16))
                    }
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 360)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(24)
        }
        .transition(.opacity)
        .onAppear { bounce = true }
    }
}
