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
                onStartNewTown: { showConfirmNewTown = true },
                showConfirmNewTown: showConfirmNewTown,
                onArchiveAndNew: {
                    Task { await town.clearActiveTown(mode: .archive) }
                    showConfirmNewTown = false
                },
                onDeleteAndNew: {
                    Task { await town.clearActiveTown(mode: .delete) }
                    showConfirmNewTown = false
                },
                onCancelNewTown: { showConfirmNewTown = false }
            )
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
    /// When true, the inline "start a new town?" confirmation panel is
    /// shown over the canvas. We render this inside the menu bar window
    /// rather than as a `.confirmationDialog` because external modals
    /// dismiss the MenuBarExtra panel.
    var showConfirmNewTown: Bool = false
    var onArchiveAndNew: () -> Void = {}
    var onDeleteAndNew: () -> Void = {}
    var onCancelNewTown: () -> Void = {}

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
            // Fixed minWidth so the header doesn't reflow when the
            // percentage grows (75% → 100% → 150% → 200% all fit).
            iconButton("\(Int(town.view.zoom * 100))%") { town.recenterCamera() }
                .frame(minWidth: 38)
            iconButton("+") { town.zoomIn() }
            iconButton(town.labelMode.glyph) { town.cycleLabelMode() }
                .help("Building labels: \(town.labelMode.label)")
            iconButton(town.dayNightMode.glyph) { town.cycleDayNightMode() }
                .help("Day/night: \(town.dayNightMode.label)")
            iconButton("🖥") { cycleCRT() }
                .help("CRT effect: \(notifier.crtMode.label)")
        }
    }

    /// Cycles through every CRTMode case so players can pick a retro
    /// scanline / phosphor / dot-matrix overlay for the whole game view.
    private func cycleCRT() {
        let modes = CRTMode.allCases
        let current = notifier.crtMode
        let next = modes.firstIndex(of: current).map { modes[($0 + 1) % modes.count] } ?? .off
        notifier.setCRTMode(next)
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
        let pop = town.state?.townsfolk.count ?? 0
        let cap = town.state.map { TokeyoTownStore.populationCap(buildingCount: $0.buildings.count) } ?? 0
        let upkeep = pop * TokeyoTownStore.upkeepPerTownsfolkPerTick
        return HStack(spacing: 8) {
            chip("💰", r.coin, kind: nil)
            chip("📜", r.knowledge, kind: .knowledge)
            chip("🔨", r.lumber, kind: .lumber)
            chip("⚙️", r.industry, kind: .industry)
            chip("🌱", r.growth, kind: .growth)
            populationChip(pop: pop, cap: cap, upkeep: upkeep)
        }
        .padding(.vertical, 2)
    }

    private func populationChip(pop: Int, cap: Int, upkeep: Int) -> some View {
        HStack(spacing: 2) {
            Text("👥").font(.system(size: 11))
            Text("\(pop)/\(cap)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white)
            Text("−\(upkeep)💰")
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(Color(red: 0.12, green: 0.12, blue: 0.16))
        .overlay(Rectangle().stroke(Color(white: 0.25), lineWidth: 0.5))
        .help("Population: \(pop) of \(cap). Costs \(upkeep) coin/tick — townsfolk leave town if you can't pay.")
    }

    private func chip(_ icon: String, _ value: Int, kind: TokeyoTownStore.TradeKind?) -> some View {
        let canBuy: Bool = {
            guard let kind, let s = town.state else { return false }
            return s.resources.coin >= TokeyoTownStore.tradeCost(for: kind)
        }()
        let chipBody = HStack(spacing: 2) {
            Text(icon).font(.system(size: 11))
            Text("\(value)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white)
            if let kind {
                Text("+\(TokeyoTownStore.tradeCost(for: kind))💰")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(canBuy
                        ? Color(red: 0.95, green: 0.85, blue: 0.30)
                        : .white.opacity(0.3))
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(Color(red: 0.12, green: 0.12, blue: 0.16))
        .overlay(Rectangle().stroke(
            (kind != nil && canBuy)
                ? Color(red: 0.95, green: 0.85, blue: 0.30).opacity(0.6)
                : Color(white: 0.25),
            lineWidth: 0.5
        ))
        if let kind {
            return AnyView(Button {
                Task { _ = await town.buyResource(kind) }
            } label: { chipBody }
            .buttonStyle(.plain)
            .help("Trade: spend \(TokeyoTownStore.tradeCost(for: kind)) coin to gain 1."))
        } else {
            return AnyView(chipBody)
        }
    }

    private var toolSidebar: some View {
        ScrollView {
            VStack(spacing: 4) {
                toolButton(.hand, icon: "🗑", label: "Remove")
                toolButton(.pan, icon: "✥", label: "Pan")
                toolButton(.road, icon: "🛣", label: "Road",
                           cost: TokeyoTownStore.roadCost)
                toolButton(.plantTree, icon: "🌳", label: "Tree",
                           cost: TokeyoTownStore.plantTreeCost)
                toolButton(.plantFlower, icon: "🌸", label: "Flower",
                           cost: TokeyoTownStore.plantFlowerCost)
                toolButton(.pond, icon: "💧", label: "Pond",
                           cost: TokeyoTownStore.pondCost)
                toolButton(.lantern, icon: "🏮", label: "Lantern",
                           cost: TokeyoTownStore.lanternCost)
                toolButton(.raise, icon: "⛰", label: "Raise",
                           cost: TokeyoTownStore.raiseCost)
                toolButton(.lower, icon: "🕳", label: "Lower",
                           cost: TokeyoTownStore.lowerCost)
            }
            .padding(.bottom, 2)
        }
        .frame(width: 60)
    }

    private func toolButton(
        _ tool: TokeyoTownStore.Tool,
        icon: String,
        label: String,
        cost: TokeyoTownState.Resources? = nil,
        refund: TokeyoTownState.Resources? = nil
    ) -> some View {
        let isSelected = town.tool == tool
        return Button {
            town.selectTool(tool)
        } label: {
            VStack(spacing: 1) {
                Text(icon).font(.system(size: 14))
                Text(label.uppercased())
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.78))
                if let cost {
                    Text(compactCostText(cost))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
                if let refund {
                    Text("+" + compactCostText(refund))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(Color(red: 0.55, green: 0.92, blue: 0.55))
                }
            }
            .padding(.vertical, 4)
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
                        hoverHighlight: currentHoverHighlight,
                        view: town.view,
                        labelMode: town.labelMode,
                        lightLevel: TimeOfDay.from(mode: town.dayNightMode,
                                                   now: context.date).lightLevel
                    )
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(point):
                            updateHover(at: point, canvas: canvasSize)
                        case .ended:
                            hoverTile = nil
                        }
                    }
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
                    if showConfirmNewTown {
                        confirmNewTownOverlay
                            .frame(width: canvasSize.width, height: canvasSize.height)
                    }
                }
            }
        }
        .frame(minHeight: 300)
    }

    /// Inline confirmation panel for "Start a new town?". Lives inside
    /// the menu bar window so it doesn't dismiss the panel — using a
    /// `.confirmationDialog` here would steal focus and close Tokade.
    private var confirmNewTownOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("START A NEW TOWN?")
                    .font(.system(.callout, design: .monospaced)).fontWeight(.bold)
                    .foregroundStyle(Color(red: 0.95, green: 0.85, blue: 0.30))
                Text("What should happen to the current town?")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                VStack(spacing: 6) {
                    confirmRow(
                        title: "Archive",
                        subtitle: "Save it to ~/.tokade/games/tokeyotown/archive/ so you can come back to it.",
                        tint: Color(red: 0.55, green: 0.78, blue: 0.95),
                        action: onArchiveAndNew
                    )
                    confirmRow(
                        title: "Delete forever",
                        subtitle: "Wipe the town save and any archived backups. Cannot be undone.",
                        tint: Color(red: 0.95, green: 0.42, blue: 0.42),
                        action: onDeleteAndNew
                    )
                    Button("Cancel") { onCancelNewTown() }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6).padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .background(Color(red: 0.20, green: 0.20, blue: 0.25))
                        .foregroundStyle(.white)
                        .overlay(Rectangle().stroke(Color(white: 0.4), lineWidth: 1))
                        .font(.system(.caption, design: .monospaced))
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: 360)
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
            .overlay(Rectangle().stroke(Color(red: 0.95, green: 0.85, blue: 0.30), lineWidth: 2))
        }
    }

    private func confirmRow(
        title: String, subtitle: String, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(.caption, design: .monospaced)).fontWeight(.bold)
                    .foregroundStyle(tint)
                Text(subtitle)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.14, green: 0.14, blue: 0.18))
            .overlay(Rectangle().stroke(tint, lineWidth: 1))
        }
        .buttonStyle(.plain)
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

    /// Yellow / red tile outline for non-build tools so the player sees
    /// which tile their next click will affect.
    private var currentHoverHighlight: IsoTileRenderer.HoverHighlight? {
        guard let tile = hoverTile, let s = town.state else { return nil }
        switch town.tool {
        case .pan, .build:
            return nil
        case .hand:
            return .init(x: tile.x, y: tile.y, valid: true)
        case .road:
            let t = s.terrain.tile(x: tile.x, y: tile.y)
            let elev = s.terrain.elev(x: tile.x, y: tile.y)
            let validTile = (t == .grass || t == .sand || t == .flower) && elev < 2
            let canAfford = s.resources.canAfford(TokeyoTownStore.roadCost)
            return .init(x: tile.x, y: tile.y, valid: validTile && canAfford)
        case .plantTree:
            let valid = s.terrain.tile(x: tile.x, y: tile.y) == .grass
                && s.resources.canAfford(TokeyoTownStore.plantTreeCost)
            return .init(x: tile.x, y: tile.y, valid: valid)
        case .plantFlower:
            let valid = s.terrain.tile(x: tile.x, y: tile.y) == .grass
                && s.resources.canAfford(TokeyoTownStore.plantFlowerCost)
            return .init(x: tile.x, y: tile.y, valid: valid)
        case .lantern:
            let valid = s.terrain.tile(x: tile.x, y: tile.y) == .grass
                && s.resources.canAfford(TokeyoTownStore.lanternCost)
            return .init(x: tile.x, y: tile.y, valid: valid)
        case .pond:
            let t = s.terrain.tile(x: tile.x, y: tile.y)
            let valid = (t == .grass || t == .sand || t == .flower)
                && s.terrain.elev(x: tile.x, y: tile.y) == 0
                && s.resources.canAfford(TokeyoTownStore.pondCost)
            return .init(x: tile.x, y: tile.y, valid: valid)
        case .raise:
            let t = s.terrain.tile(x: tile.x, y: tile.y)
            let valid = s.terrain.elev(x: tile.x, y: tile.y) < 4
                && t != .road
                && s.resources.canAfford(TokeyoTownStore.raiseCost)
            return .init(x: tile.x, y: tile.y, valid: valid)
        case .lower:
            let t = s.terrain.tile(x: tile.x, y: tile.y)
            let valid = s.terrain.elev(x: tile.x, y: tile.y) > 0
                && t != .road
                && s.resources.canAfford(TokeyoTownStore.lowerCost)
            return .init(x: tile.x, y: tile.y, valid: valid)
        }
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

    /// Tick interval used to scale animation phase. Must match the
    /// background loop in TokadeApp (~3 s) so the npc walk animation
    /// finishes exactly when the next AI tick fires — no visual
    /// teleport-back-to-start when phase wraps.
    private static let tickInterval: Double = 3.0

    /// Animation phase ∈ [0, 1]. Anchored to `state.lastTickAt` so it
    /// rises smoothly from 0 to 1 between AI ticks and stays clamped
    /// at 1 if the next tick is late.
    private func phaseValue(at date: Date) -> Double {
        guard let s = town.state else { return 0 }
        let elapsed = date.timeIntervalSince(s.lastTickAt)
        return max(0, min(1, elapsed / Self.tickInterval))
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
