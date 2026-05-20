import SwiftUI

/// The Arcade-tab subview for Tokeyo Town. Routes between:
///   - new-town flow when no town exists
///   - in-game view when a town is loaded
///
/// Mirrors the TokenGaidenTab integration pattern.
@MainActor
struct TokeyoTownTab: View {
    @Bindable var town: TokeyoTownStore
    @Bindable var usage: UsageStore
    @Bindable var notifier: Notifier
    var onExitGame: () -> Void

    @State private var showConfirmNewTown = false

    var body: some View {
        if town.state != nil {
            TokeyoTownGameView(
                town: town,
                notifier: notifier,
                onExitGame: onExitGame,
                onStartNewTown: { showConfirmNewTown = true }
            )
            .confirmationDialog(
                "Start a new town?",
                isPresented: $showConfirmNewTown
            ) {
                Button("Start new town", role: .destructive) {
                    Task { await town.eraseAll() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The current town will be archived to ~/.tokade/games/tokeyotown/archive/. You can only have one town at a time in this version.")
            }
        } else {
            NewTownView(store: town, usage: usage, notifier: notifier, onCancel: onExitGame)
        }
    }
}

@MainActor
struct TokeyoTownGameView: View {
    @Bindable var town: TokeyoTownStore
    @Bindable var notifier: Notifier
    var onExitGame: () -> Void
    var onStartNewTown: () -> Void

    var body: some View {
        GameScreen(crtMode: notifier.crtMode) {
            VStack(spacing: 6) {
                header
                resourceBar
                TimelineView(.animation) { context in
                    let phase = phaseValue(at: context.date)
                    GeometryReader { geo in
                        let canvasSize = geo.size
                        IsoTileRenderer(
                            state: town.state ?? sentinelState,
                            phase: phase,
                            placementPreview: nil
                        )
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    handleTap(at: value.location, canvas: canvasSize)
                                }
                        )
                    }
                }
                .frame(minHeight: 200)
                buildingPalette
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sentinelState: TokeyoTownState {
        TokeyoTownState.fresh(
            townId: "—",
            repo: .init(
                path: "/",
                displayName: "—",
                scannedAt: .now,
                primaryLanguage: "unknown",
                biome: .plain,
                era: .modern,
                ageInDays: 0,
                loc: 0,
                mapSize: 16,
                contributorCount: 0,
                lushness: 0.5
            )
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button("← Arcade") { onExitGame() }
                .buttonStyle(.plain)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            if let s = town.state {
                Text(s.repo.displayName.uppercased())
                    .font(.system(.callout, design: .monospaced)).fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("· \(BiomeCatalog.info(s.repo.biome).displayName) ·")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Button("New…") { onStartNewTown() }
                .buttonStyle(.plain)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var resourceBar: some View {
        let r = town.state?.resources ?? .zero
        return HStack(spacing: 10) {
            chip("💰", r.coin)
            chip("📜", r.knowledge)
            chip("🔨", r.lumber)
            chip("⚙️", r.industry)
            chip("🛡", r.stability)
            chip("✨", r.inspiration)
            chip("🌱", r.growth)
        }
        .padding(.vertical, 4)
    }

    private func chip(_ icon: String, _ value: Int) -> some View {
        HStack(spacing: 2) {
            Text(icon).font(.system(size: 11))
            Text("\(value)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(Color(red: 0.12, green: 0.12, blue: 0.16))
        .overlay(Rectangle().stroke(Color(white: 0.25), lineWidth: 0.5))
    }

    private var buildingPalette: some View {
        let biome = town.state?.repo.biome ?? .plain
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    town.selectBuilding(nil)
                } label: {
                    Text("✋")
                        .font(.system(size: 14))
                        .padding(6)
                        .background(town.pendingPlacement == nil
                                    ? Color(red: 0.95, green: 0.85, blue: 0.30)
                                    : Color(red: 0.18, green: 0.18, blue: 0.22))
                        .foregroundStyle(town.pendingPlacement == nil ? .black : .white)
                        .overlay(Rectangle().stroke(Color(white: 0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)

                ForEach(BuildingCatalog.buildings(for: biome)) { b in
                    Button {
                        town.selectBuilding(b.id)
                    } label: {
                        VStack(spacing: 2) {
                            Text(b.glyph).font(.system(size: 16))
                            Text(b.displayName.uppercased())
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.75))
                            costRow(b.cost)
                        }
                        .frame(width: 64)
                        .padding(4)
                        .background(
                            town.pendingPlacement == b.id
                                ? Color(red: 0.95, green: 0.85, blue: 0.30).opacity(0.25)
                                : Color(red: 0.12, green: 0.12, blue: 0.16)
                        )
                        .overlay(
                            Rectangle().stroke(
                                town.pendingPlacement == b.id
                                    ? Color(red: 0.95, green: 0.85, blue: 0.30)
                                    : Color(white: 0.25),
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .help(b.blurb)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 80)
    }

    private func costRow(_ r: TokeyoTownState.Resources) -> some View {
        HStack(spacing: 2) {
            if r.coin > 0 { Text("💰\(r.coin)").font(.system(size: 7, design: .monospaced)) }
            if r.knowledge > 0 { Text("📜\(r.knowledge)").font(.system(size: 7, design: .monospaced)) }
            if r.lumber > 0 { Text("🔨\(r.lumber)").font(.system(size: 7, design: .monospaced)) }
            if r.industry > 0 { Text("⚙️\(r.industry)").font(.system(size: 7, design: .monospaced)) }
            if r.stability > 0 { Text("🛡\(r.stability)").font(.system(size: 7, design: .monospaced)) }
            if r.inspiration > 0 { Text("✨\(r.inspiration)").font(.system(size: 7, design: .monospaced)) }
            if r.growth > 0 { Text("🌱\(r.growth)").font(.system(size: 7, design: .monospaced)) }
        }
        .foregroundStyle(.white.opacity(0.7))
    }

    private func phaseValue(at date: Date) -> Double {
        let secs = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.0)
        return secs / 2.0
    }

    private func handleTap(at point: CGPoint, canvas: CGSize) {
        guard let mapSize = town.state?.repo.mapSize,
              let tile = IsoMath.unproject(point, mapSize: mapSize, canvas: canvas) else { return }
        if town.pendingPlacement == nil {
            Task { await town.demolishAt(x: tile.x, y: tile.y) }
        } else {
            Task { _ = await town.placeAt(x: tile.x, y: tile.y) }
        }
    }
}
