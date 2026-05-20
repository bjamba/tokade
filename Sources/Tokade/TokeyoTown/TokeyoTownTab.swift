import SwiftUI

/// The Arcade-tab subview for Tokeyo Town. Routes between:
///   - new-town flow when no town exists
///   - in-game view when a town is loaded
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

    @State private var hoverTile: (x: Int, y: Int)?
    @State private var dragStartPan: (x: CGFloat, y: CGFloat)?
    @State private var dragStartLocation: CGPoint?

    /// True when the Pan tool is selected — drags then move the camera
    /// instead of applying a tool to tiles.
    private var panMode: Bool { town.tool == .pan }

    var body: some View {
        GameScreen(crtMode: notifier.crtMode) {
            VStack(spacing: 4) {
                header
                resourceBar
                HStack(alignment: .top, spacing: 6) {
                    toolSidebar
                    canvasArea
                }
                bottomBar
            }
            .padding(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button("← Arcade") { onExitGame() }
                .buttonStyle(.plain)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            iconButton(town.canUndo ? "↶ Undo" : "↶") {
                Task { await town.undo() }
            }
            .disabled(!town.canUndo)
            iconButton(town.canRedo ? "↷ Redo" : "↷") {
                Task { await town.redo() }
            }
            .disabled(!town.canRedo)
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
            cameraControls
            Button("New…") { onStartNewTown() }
                .buttonStyle(.plain)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var cameraControls: some View {
        HStack(spacing: 2) {
            iconButton("−") { town.zoomOut() }
            iconButton("\(Int(town.view.zoom * 100))%") { town.recenterCamera() }
            iconButton("+") { town.zoomIn() }
        }
    }

    private func iconButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color(red: 0.12, green: 0.12, blue: 0.16))
                .overlay(Rectangle().stroke(Color(white: 0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var resourceBar: some View {
        let r = town.state?.resources ?? .zero
        return HStack(spacing: 8) {
            chip("💰", r.coin)
            chip("📜", r.knowledge)
            chip("🔨", r.lumber)
            chip("⚙️", r.industry)
            chip("🛡", r.stability)
            chip("✨", r.inspiration)
            chip("🌱", r.growth)
        }
        .padding(.vertical, 2)
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

    private var toolSidebar: some View {
        ScrollView {
            VStack(spacing: 4) {
                toolButton(.hand, icon: "🗑", label: "Remove",
                           subtitle: "any tile")
                toolButton(.pan, icon: "✥", label: "Pan",
                           subtitle: "drag map")
                toolButton(.road, icon: "🛣", label: "Road",
                           cost: TokeyoTownStore.roadCost, costPrefix: "/tile")
                toolButton(.plantTree, icon: "🌱", label: "Plant",
                           cost: TokeyoTownStore.plantTreeCost)
                toolButton(.clearTree, icon: "🪓", label: "Fell",
                           cost: TokeyoTownStore.clearTreeCost,
                           refund: TokeyoTownStore.clearTreeRefund)
                toolButton(.levelRock, icon: "⛏", label: "Level",
                           cost: TokeyoTownStore.levelRockCost)
                toolButton(.raise, icon: "⛰", label: "Raise",
                           cost: TokeyoTownStore.raiseCost)
                toolButton(.lower, icon: "🕳", label: "Lower",
                           cost: TokeyoTownStore.lowerCost)
                toolButton(.plantFlower, icon: "🌸", label: "Flower",
                           cost: TokeyoTownStore.plantFlowerCost)
                toolButton(.lantern, icon: "🏮", label: "Lantern",
                           cost: TokeyoTownStore.lanternCost)
            }
            .padding(.bottom, 2)
        }
        .frame(width: 66)
    }

    private func toolButton(
        _ tool: TokeyoTownStore.Tool,
        icon: String,
        label: String,
        subtitle: String? = nil,
        cost: TokeyoTownState.Resources? = nil,
        refund: TokeyoTownState.Resources? = nil,
        costPrefix: String? = nil
    ) -> some View {
        let isSelected = town.tool == tool
        return Button {
            town.selectTool(tool)
        } label: {
            VStack(spacing: 1) {
                Text(icon).font(.system(size: 14))
                Text(label.uppercased())
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                if let subtitle {
                    Text(subtitle.uppercased())
                        .font(.system(size: 6, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
                if let cost {
                    Text(compactCostText(cost) + (costPrefix ?? ""))
                        .font(.system(size: 6, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
                if let refund {
                    Text("+" + compactCostText(refund))
                        .font(.system(size: 6, design: .monospaced))
                        .foregroundStyle(Color(red: 0.55, green: 0.92, blue: 0.55))
                }
            }
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background(isSelected
                ? Color(red: 0.95, green: 0.85, blue: 0.30).opacity(0.25)
                : Color(red: 0.12, green: 0.12, blue: 0.16))
            .overlay(Rectangle().stroke(
                isSelected ? Color(red: 0.95, green: 0.85, blue: 0.30) : Color(white: 0.25),
                lineWidth: 1
            ))
        }
        .buttonStyle(.plain)
    }

    private func compactCostText(_ r: TokeyoTownState.Resources) -> String {
        var parts: [String] = []
        if r.coin > 0 { parts.append("💰\(r.coin)") }
        if r.knowledge > 0 { parts.append("📜\(r.knowledge)") }
        if r.lumber > 0 { parts.append("🔨\(r.lumber)") }
        if r.industry > 0 { parts.append("⚙️\(r.industry)") }
        if r.stability > 0 { parts.append("🛡\(r.stability)") }
        if r.inspiration > 0 { parts.append("✨\(r.inspiration)") }
        if r.growth > 0 { parts.append("🌱\(r.growth)") }
        return parts.joined(separator: " ")
    }

    private var canvasArea: some View {
        TimelineView(.animation) { context in
            let phase = phaseValue(at: context.date)
            GeometryReader { geo in
                let canvasSize = geo.size
                ZStack(alignment: .topLeading) {
                    IsoTileRenderer(
                        state: town.state ?? sentinelState,
                        phase: phase,
                        placementPreview: currentPreview,
                        view: town.view
                    )
                    .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if panMode {
                                continuePan(value: v)
                            } else {
                                updateHover(at: v.location, canvas: canvasSize)
                            }
                        }
                        .onEnded { v in
                            if panMode {
                                continuePan(value: v)
                                dragStartPan = nil
                                dragStartLocation = nil
                            } else if let start = dragStartLocation,
                                      hypot(v.location.x - start.x, v.location.y - start.y) < 4 {
                                handleTap(at: v.location, canvas: canvasSize)
                                dragStartLocation = nil
                            } else {
                                dragStartLocation = nil
                                handleTap(at: v.location, canvas: canvasSize)
                            }
                        }
                )
                    currentToolIndicator
                        .padding(6)
                }
            }
        }
        .frame(minHeight: 300)
    }

    private var currentToolIndicator: some View {
        HStack(spacing: 4) {
            Text(town.tool.glyph).font(.system(size: 13))
            Text(town.tool.displayName.uppercased())
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            Color(red: 0.08, green: 0.08, blue: 0.12).opacity(0.85)
        )
        .overlay(Rectangle().stroke(Color(red: 0.95, green: 0.85, blue: 0.30), lineWidth: 1))
    }

    private func continuePan(value: DragGesture.Value) {
        if dragStartPan == nil {
            dragStartPan = (town.view.panX, town.view.panY)
            dragStartLocation = value.startLocation
        }
        guard let startPan = dragStartPan else { return }
        let dx = value.translation.width
        let dy = value.translation.height
        town.view.panX = startPan.x + dx
        town.view.panY = startPan.y + dy
    }

    private var currentPreview: IsoTileRenderer.PlacementPreview? {
        guard case let .build(id) = town.tool, let tile = hoverTile else { return nil }
        return IsoTileRenderer.PlacementPreview(
            kind: id, tile: tile,
            valid: town.canPlaceBuilding(id, at: tile.x, y: tile.y)
        )
    }

    private func updateHover(at point: CGPoint, canvas: CGSize) {
        guard let mapSize = town.state?.repo.mapSize else { return }
        if dragStartLocation == nil { dragStartLocation = point }
        hoverTile = IsoMath.unproject(point, mapSize: mapSize, canvas: canvas, view: town.view)
    }

    private var bottomBar: some View {
        let biome = town.state?.repo.biome ?? .plain
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(BuildingCatalog.buildings(for: biome)) { b in
                    Button {
                        town.selectTool(.build(b.id))
                    } label: {
                        VStack(spacing: 1) {
                            Text(b.glyph).font(.system(size: 14))
                            Text(b.displayName.uppercased())
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                            Text(compactCostText(b.cost))
                                .font(.system(size: 6, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                            HStack(spacing: 2) {
                                if b.shape.footprint.w > 1 || b.shape.footprint.h > 1 {
                                    Text("\(b.shape.footprint.w)×\(b.shape.footprint.h)")
                                        .font(.system(size: 6, design: .monospaced))
                                        .foregroundStyle(Color(red: 0.95, green: 0.85, blue: 0.30))
                                }
                                if b.isHome {
                                    Text("HOME")
                                        .font(.system(size: 6, design: .monospaced))
                                        .foregroundStyle(Color(red: 0.55, green: 0.92, blue: 0.55))
                                }
                            }
                        }
                        .frame(width: 64)
                        .padding(3)
                        .background(
                            town.pendingPlacement == b.id
                                ? Color(red: 0.95, green: 0.85, blue: 0.30).opacity(0.25)
                                : Color(red: 0.12, green: 0.12, blue: 0.16)
                        )
                        .overlay(Rectangle().stroke(
                            town.pendingPlacement == b.id
                                ? Color(red: 0.95, green: 0.85, blue: 0.30)
                                : Color(white: 0.25),
                            lineWidth: 1
                        ))
                    }
                    .buttonStyle(.plain)
                    .help(b.blurb)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 84)
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

    private func phaseValue(at date: Date) -> Double {
        let secs = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.0)
        return secs / 2.0
    }

    private func handleTap(at point: CGPoint, canvas: CGSize) {
        guard !panMode,
              let mapSize = town.state?.repo.mapSize,
              let tile = IsoMath.unproject(point,
                                           mapSize: mapSize,
                                           canvas: canvas,
                                           view: town.view) else { return }
        Task { _ = await town.applyToolAt(x: tile.x, y: tile.y) }
    }
}
