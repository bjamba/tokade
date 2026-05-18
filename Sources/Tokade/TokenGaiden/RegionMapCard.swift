import SwiftUI

/// 2D spatial map of all visited regions. Each region has a stable position
/// (hash-based, assigned on first discovery) so the map layout is
/// consistent across launches. Player clicks a region tile to fast-travel
/// (pin) — the highlighted tile shows where they are now, and the pinned
/// tile is rendered with a thicker accent border. Map fills whatever
/// vertical space the parent gives it so the nav bar stays put.
@MainActor
struct RegionMapCard: View {
    @Bindable var gaiden: TokenGaidenStore
    let state: TokegotchiState

    /// Cap on regions rendered to keep the map readable. Older regions
    /// still live in state — they just don't paint until they become a
    /// top-N recent again. The current + pinned region are always
    /// included regardless of recency.
    private let maxRegionsShown = 10

    var body: some View {
        let allRegions = Array((state.world.flavors ?? [:]).keys)
        let visited = topRegions(from: allRegions)
        if visited.isEmpty {
            VStack {
                Spacer()
                Text("Use Claude Code to discover regions.")
                    .gameFont(.small).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            mapCanvas(regions: visited)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black.opacity(0.2), lineWidth: 1)
                )
        }
    }

    /// Map canvas — baked pixel-art overworld background with biome tiles
    /// plotted at each region's persisted position.
    private func mapCanvas(regions: [String]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                worldBackground(width: w, height: h)
                ForEach(regions, id: \.self) { region in
                    regionTile(region, canvasWidth: w, canvasHeight: h)
                }
            }
            .frame(width: w, height: h)
        }
    }

    /// Hand-authored pixel-art world map rendered as the map background.
    /// Falls back to a parchment gradient if the matrix isn't bundled.
    @ViewBuilder
    private func worldBackground(width w: CGFloat, height h: CGFloat) -> some View {
        if let m = WorldMapArt.tile, let palette = WorldMapArt.palette {
            let scale = max(1, Int(min(w / 128, h / 96)))
            let img = SpriteRenderer.render(m, palette: palette, scale: scale)
            Image(nsImage: img)
                .interpolation(.none)
                .resizable()
                .scaledToFill()
                .frame(width: w, height: h)
                .clipped()
        } else {
            LinearGradient(
                colors: [Color(red: 0.96, green: 0.92, blue: 0.80),
                         Color(red: 0.86, green: 0.78, blue: 0.62)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: w, height: h)
        }
    }

    /// One biome tile at the region's persisted position. Visual state:
    /// - current region: accent border + larger tile
    /// - pinned region: gold border (and accent if also current)
    /// - recently active: green pulse outline
    private func regionTile(_ region: String, canvasWidth w: CGFloat, canvasHeight h: CGFloat) -> some View {
        let pos = position(for: region)
        let isHere   = state.world.currentRegion == region
        let isPinned = state.world.pinnedRegion == region
        let isLive   = (state.world.lastActiveAt?[region])
            .map { Date().timeIntervalSince($0) < 60 } ?? false
        let flavor = state.world.flavors?[region] ?? .wilderness
        let tileSize: CGFloat = isHere ? 64 : 48
        return Button {
            // Toggle pin: clicking the already-pinned region unpins.
            Task { await gaiden.fastTravel(to: isPinned ? nil : region) }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    if isLive {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.green, lineWidth: 2)
                            .frame(width: tileSize + 8, height: tileSize + 8)
                    }
                    if isPinned {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(red: 0.95, green: 0.78, blue: 0.20), lineWidth: 3)
                            .frame(width: tileSize + 4, height: tileSize + 4)
                    } else if isHere {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor, lineWidth: 3)
                            .frame(width: tileSize + 4, height: tileSize + 4)
                    }
                    biomeImage(flavor: flavor, size: tileSize)
                }
                Text(region.split(separator: "/").last.map(String.init) ?? region)
                    .font(.system(size: 9, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 3)
                    .background(Color(white: 1, opacity: 0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .buttonStyle(.plain)
        .position(x: pos.x * w, y: pos.y * h)
        .help(isPinned ? "Click to unpin \(region)" : "Click to travel to \(region)")
    }

    @ViewBuilder
    private func biomeImage(flavor: Region.Flavor, size: CGFloat) -> some View {
        if let tile = BiomeArt.tile(for: flavor) {
            let scale = max(1, Int(size / 32))
            let renderedSize = CGFloat(32 * scale)
            let img = SpriteRenderer.render(tile, palette: BiomeArt.palette(for: flavor), scale: scale)
            Image(nsImage: img)
                .interpolation(.none)
                .resizable()
                .frame(width: renderedSize, height: renderedSize)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Rectangle()
                .fill(flavorColor(flavor))
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func position(for region: String) -> (x: Double, y: Double) {
        if let arr = state.world.regionPositions?[region], arr.count == 2 {
            return (arr[0], arr[1])
        }
        return Region.position(for: region)
    }

    /// Pick the top N regions to render. Always includes the current and
    /// pinned region (so the player can always see where they are), then
    /// fills the remainder by `lastActiveAt` recency. Untimed regions sort
    /// last, broken by name to keep the order stable.
    private func topRegions(from all: [String]) -> [String] {
        guard all.count > maxRegionsShown else { return all.sorted() }
        var keep = Set<String>()
        if let here = state.world.currentRegion, all.contains(here) { keep.insert(here) }
        if let pin = state.world.pinnedRegion, all.contains(pin) { keep.insert(pin) }
        let lastActive = state.world.lastActiveAt ?? [:]
        let byRecency = all.sorted { a, b in
            let ta = lastActive[a] ?? .distantPast
            let tb = lastActive[b] ?? .distantPast
            if ta == tb { return a < b }
            return ta > tb
        }
        for r in byRecency {
            if keep.count >= maxRegionsShown { break }
            keep.insert(r)
        }
        return Array(keep).sorted()
    }

    private func flavorColor(_ flavor: Region.Flavor) -> Color {
        switch flavor {
        case .stonework:     return Color(red: 0.55, green: 0.55, blue: 0.55)
        case .ironFortress:  return Color(red: 0.45, green: 0.40, blue: 0.50)
        case .gardenVillage: return Color(red: 0.40, green: 0.70, blue: 0.45)
        case .bazaar:        return Color(red: 0.85, green: 0.55, blue: 0.30)
        case .openSteppe:    return Color(red: 0.80, green: 0.75, blue: 0.50)
        case .wilderness:    return Color(red: 0.35, green: 0.55, blue: 0.65)
        }
    }
}
