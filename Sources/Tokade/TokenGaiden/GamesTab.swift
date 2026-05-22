import SwiftUI

/// Container tab for any games we ship. Currently has one — Token Gaiden RPG
/// — but the launcher screen leaves room for more. Selecting a game enters
/// it; back-arrow returns to the launcher.
@MainActor
struct GamesTab: View {
    @Bindable var gaiden: TokenGaidenStore
    @Bindable var town: TokeyoTownStore
    @Bindable var store: UsageStore
    @Bindable var notifier: Notifier
    @State private var selectedGame: Game?

    enum Game: String, Identifiable, Hashable, CaseIterable {
        case tokenGaidenRPG
        case tokeyoTown
        var id: String { rawValue }
        var bannerId: String {
            switch self {
            case .tokenGaidenRPG: return "token-gaiden-rpg"
            case .tokeyoTown: return "tokeyo-town"
            }
        }

        var title: String {
            switch self {
            case .tokenGaidenRPG: return "Token Gaiden RPG"
            case .tokeyoTown: return "Tokeyo Town"
            }
        }

        var subtitle: String {
            switch self {
            case .tokenGaidenRPG:
                return "A roguelike fed by your Claude Code usage."
            case .tokeyoTown:
                return "Cozy isometric sandbox. One town per repo."
            }
        }
    }

    var body: some View {
        if let game = selectedGame {
            switch game {
            case .tokenGaidenRPG:
                TokenGaidenTab(gaiden: gaiden, store: store, notifier: notifier, onExitGame: {
                    selectedGame = nil
                })
            case .tokeyoTown:
                TokeyoTownTab(town: town, usage: store, notifier: notifier, onExitGame: {
                    selectedGame = nil
                })
            }
        } else {
            launcher
        }
    }

    private var launcher: some View {
        GameScreen(crtMode: notifier.crtMode) {
            VStack(spacing: 8) {
                Text("GAMES")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(Color(red: 0.95, green: 0.85, blue: 0.30))
                Rectangle().fill(Color(white: 0.3)).frame(height: 1)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Game.allCases) { game in
                            gameCard(game)
                        }
                        comingSoonCard
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func gameCard(_ game: Game) -> some View {
        Button {
            selectedGame = game
        } label: {
            VStack(spacing: 0) {
                bannerImage(for: game)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.title.uppercased())
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text(game.subtitle)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Text("▶ PLAY")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(Color(red: 0.95, green: 0.85, blue: 0.30))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.12, green: 0.12, blue: 0.16))
            }
            .overlay(Rectangle().stroke(Color(red: 0.95, green: 0.85, blue: 0.30), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func bannerImage(for game: Game) -> some View {
        if let sprite = GameBanner.sprite(for: game.bannerId) {
            let img = SpriteRenderer.render(sprite,
                                            palette: GameBanner.palette(for: game.bannerId),
                                            scale: 3)
            Image(nsImage: img)
                .interpolation(.none)
                .resizable()
                .aspectRatio(128.0 / 48.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
        } else if game == .tokeyoTown {
            // v3.13 — procedural banner; saves us from hand-authoring
            // a 128×48 matrix file and stays in sync with the in-game
            // iso-prism look.
            TokeyoTownBanner()
        } else {
            Rectangle()
                .fill(Color(red: 0.18, green: 0.18, blue: 0.22))
                .frame(height: 96)
        }
    }

    private var comingSoonCard: some View {
        Text("MORE COMING SOON")
            .font(.system(.caption, design: .monospaced)).fontWeight(.bold)
            .foregroundStyle(.white.opacity(0.4))
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
            .overlay(Rectangle().stroke(Color(white: 0.3), lineWidth: 1))
    }
}
