import SwiftUI

/// The Token Gaiden tab — v1 lives inside the existing Tokade panel.
///
/// First launch shows a character creator. Once a Tokegotchi exists, the tab
/// renders the live sprite, stats, vitals, age, and recent telemetry-driven
/// drops. Encounters, quests, regions, and combat land in subsequent PRs.
@MainActor
struct TokenGaidenTab: View {
    @Bindable var gaiden: TokenGaidenStore
    @Bindable var store: UsageStore
    @Bindable var notifier: Notifier
    /// Called when the player picks "Exit" from Settings — wired by the
    /// host (GamesTab) to return to the launcher. Optional so previews and
    /// tests can render the tab standalone.
    var onExitGame: (() -> Void)?
    @State private var wardrobeOpen = false
    @State private var settingsOpen = false
    /// Draft equipment used while previewing in the wardrobe. nil means "no
    /// draft, render the actual saved equipment". Reset on close.
    @State private var draftCosmetic: [String: String?]?

    var body: some View {
        Group {
            if let state = gaiden.state {
                if state.isDead {
                    GameScreen(crtMode: notifier.crtMode) {
                        ScrollView {
                            DeathScreen(gaiden: gaiden, dead: state, notifier: notifier).padding(8)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    aliveLayout(state)
                }
            } else {
                // Initial hatch UI in the same emulator-screen format as the
                // rest of the game.
                GameScreen(crtMode: notifier.crtMode) {
                    VStack(spacing: 6) {
                        arcadeBackBar
                        Text("NEW GAME")
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(Color(red: 0.95, green: 0.85, blue: 0.30))
                        Rectangle().fill(Color(white: 0.3)).frame(height: 1)
                        ScrollView {
                            CharacterCreator(gaiden: gaiden, notifier: notifier)
                                .padding(.vertical, 6)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await gaiden.tick(against: store.events,
                              usedPercentage: store.rateLimits?.fiveHour?.usedPercentage)
        }
        .onChange(of: store.lastUpdated) { _, _ in
            Task { await gaiden.tick(against: store.events,
                              usedPercentage: store.rateLimits?.fiveHour?.usedPercentage) }
        }
    }

    // MARK: - Alive layout

    @State private var screen: Screen = .menu
    @State private var menuSubPage: MenuPage = .profile

    enum Screen: String, CaseIterable, Identifiable {
        case menu, town, map
        var id: String { rawValue }
        var glyph: String {
            switch self {
            case .menu: return "📋"
            case .town: return "🏘"
            case .map:  return "🗺"
            }
        }

        var label: String {
            switch self {
            case .menu: return "MENU"
            case .town: return "REGION"
            case .map:  return "MAP"
            }
        }
    }

    /// JRPG-style start menu pages. Selecting one opens its detail panel
    /// inside the Menu screen.
    enum MenuPage: String, CaseIterable, Identifiable {
        case profile, items, equip, wardrobe, achievements, hall, settings
        var id: String { rawValue }
        var glyph: String {
            switch self {
            case .profile:      return "👤"
            case .items:        return "🎒"
            case .equip:        return "🗡"
            case .wardrobe:     return "👕"
            case .achievements: return "🏅"
            case .hall:         return "🏆"
            case .settings:     return "⚙"
            }
        }

        var label: String {
            switch self {
            case .profile:      return "PROFILE"
            case .items:        return "ITEMS"
            case .equip:        return "EQUIP"
            case .wardrobe:     return "WARDROBE"
            case .achievements: return "ACHIEVE"
            case .hall:         return "HALL"
            case .settings:     return "SETTINGS"
            }
        }
    }

    private func aliveLayout(_ state: TokegotchiState) -> some View {
        GameScreen(crtMode: notifier.crtMode) {
            VStack(spacing: 6) {
                arcadeBackBar
                topResourceBar(state)
                Rectangle().fill(Color(white: 0.3)).frame(height: 1)
                ZStack(alignment: .top) {
                    contentForCurrentScreen(state)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    if let battle = state.activeBattle {
                        battleOverlay(state: state, battle: battle)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(Color(white: 0.3)).frame(height: 1)
                bottomMenu(state)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func contentForCurrentScreen(_ state: TokegotchiState) -> some View {
        switch screen {
        case .menu: menuScreen(state)
        case .town: townScreen(state)
        case .map:  mapScreen(state)
        }
    }

    /// JRPG-style start menu — left-side sub-page picker + right-side detail.
    private func menuScreen(_ state: TokegotchiState) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(MenuPage.allCases) { p in
                    menuPageButton(p)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 100)
            ZStack {
                Rectangle().fill(Color(red: 0.10, green: 0.10, blue: 0.14))
                Rectangle().stroke(Color(red: 0.40, green: 0.40, blue: 0.45), lineWidth: 1)
                menuDetail(state)
                    .padding(8)
            }
        }
    }

    private func menuPageButton(_ p: MenuPage) -> some View {
        Button {
            menuSubPage = p
        } label: {
            HStack(spacing: 6) {
                Text(p.glyph).font(.system(size: 14))
                Text(p.label)
                    .font(.system(size: 10, design: .monospaced))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(menuSubPage == p
                        ? Color(red: 0.28, green: 0.40, blue: 0.65)
                        : Color(red: 0.18, green: 0.18, blue: 0.22))
            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            .foregroundStyle(menuSubPage == p ? Color.white : Color.gray)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func menuDetail(_ state: TokegotchiState) -> some View {
        // Leaving the wardrobe sub-page discards any unapplied draft so
        // a locked silhouette previewed in the carousel can't bleed into
        // other views (Profile, etc).
        let _ = (menuSubPage != .wardrobe) ? clearWardrobeDraftIfNeeded() : ()
        switch menuSubPage {
        case .profile:      profileDetail(state)
        case .items:        ScrollView { inventoryCard(state) }
        case .equip:        ScrollView { gearCard(state) }
        case .wardrobe:     wardrobeDetail(state)
        case .achievements: ScrollView { achievementsCard(state) }
        case .hall:         hallDetail(state)
        case .settings:     ScrollView { settingsCard }
        }
    }

    /// Drop the wardrobe draft if it's stale (we're not on the wardrobe
    /// page). Idempotent — does nothing if the draft is already nil.
    private func clearWardrobeDraftIfNeeded() {
        if draftCosmetic != nil {
            DispatchQueue.main.async {
                draftCosmetic = nil
                wardrobeOpen = false
            }
        }
    }

    private func profileDetail(_ state: TokegotchiState) -> some View {
        ScrollView { heroCard(state) }
    }

    private func wardrobeDetail(_ state: TokegotchiState) -> some View {
        // Auto-prime the draft so the carousel is editable on first view.
        let outfit = draftCosmetic ?? state.inventory.equippedCosmetic
        let owned = Set(state.inventory.discoveredCosmetics ?? CosmeticCatalog.starters.map(\.id))
        // Split the draft outfit into "real" (owned, painted normally) and
        // "preview" (locked, painted as silhouette).
        var realOutfit: [String: String?] = [:]
        var lockedOutfit: [String: String?] = [:]
        for (slot, name) in outfit {
            if let n = name, !owned.contains(n) {
                lockedOutfit[slot] = n
            } else {
                realOutfit[slot] = name
            }
        }
        let palette = Palette.from(
            skin: state.identity.appearance.skinSwatch,
            iris: state.identity.appearance.irisSwatch,
            hair: state.identity.appearance.hairSwatch
        )
        let frames = BundledSprites.breathingCycle
        let realFrames = BundledSprites.compose(frames: frames, equipped: realOutfit)
        let lockedFrames = lockedOutfit.isEmpty
            ? []
            : BundledSprites.composeLayersOnly(frames: frames, equipped: lockedOutfit)
        // Cosmetics currently being previewed but not owned — surface their
        // unlock hints in a panel under the wardrobe so the carousel row
        // doesn't have to truncate them.
        let lockedHints: [(slot: String, cos: Cosmetic)] = outfit.compactMap { (slot, name) in
            guard let n = name, !owned.contains(n), let c = CosmeticCatalog.find(n) else { return nil }
            _ = slot
            return (slot, c)
        }
        return HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 4) {
                ZStack {
                    SpriteView(
                        frames: realFrames,
                        palette: palette,
                        scale: 3,
                        fps: 3,
                        crt: notifier.crtMode
                    )
                    if !lockedFrames.isEmpty {
                        // Silhouette overlay — locked layers rendered in one
                        // dark tone so the player sees the shape without
                        // spoiling the colors.
                        SpriteView(
                            frames: lockedFrames,
                            palette: Palette.silhouette,
                            scale: 3,
                            fps: 3,
                            crt: .off
                        )
                        .opacity(0.7)
                    }
                }
                .frame(width: 96, height: 162)
                Text(state.identity.name)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    wardrobeCarousel(state)
                        .onAppear {
                            if draftCosmetic == nil {
                                draftCosmetic = state.inventory.equippedCosmetic
                                wardrobeOpen = true
                            }
                        }
                    if !lockedHints.isEmpty {
                        lockedHintsPanel(lockedHints)
                    }
                }
            }
        }
    }

    private func hallDetail(_ state: TokegotchiState) -> some View {
        ScrollView {
            if state.bloodline.ancestors.isEmpty {
                Text("No ancestors yet. The Hall fills as your Tokegotchi line carries on.")
                    .gameFont(.small).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HallOfFameCard(state: state)
            }
        }
    }

    /// v3.11 — small "← Arcade" row at the top of every Token Gaiden
    /// screen, matching Tokeyo Town's idiom. Quietly leaves the game
    /// back to the arcade lobby; the in-Settings "Exit game" button
    /// stays around as a redundant control.
    @ViewBuilder
    private var arcadeBackBar: some View {
        if let onExitGame {
            HStack {
                Button("← Arcade") { onExitGame() }
                    .buttonStyle(.plain)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
        }
    }

    private func topResourceBar(_ state: TokegotchiState) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.identity.name)
                    .font(.system(.caption, design: .monospaced)).fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("Gen \(state.identity.generation)")
                    .font(.system(size: 8, design: .monospaced)).foregroundStyle(.gray)
            }
            .frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("HP").font(.system(size: 9, design: .monospaced)).foregroundStyle(GamePalette.hp)
                    PixelBar(value: state.vitals.hp, max: state.vitals.hpMax, color: GamePalette.hp, width: 80)
                    Text("\(state.vitals.hp)/\(state.vitals.hpMax)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.white).monospacedDigit()
                }
                HStack(spacing: 4) {
                    Text("SP").font(.system(size: 9, design: .monospaced)).foregroundStyle(GamePalette.sp)
                    PixelBar(value: state.vitals.sp, max: state.vitals.spMax, color: GamePalette.sp, width: 80)
                    Text("\(state.vitals.sp)/\(state.vitals.spMax)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.white).monospacedDigit()
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("EXP \(state.progress.exp)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(GamePalette.exp).monospacedDigit()
                Text("🪙 \(state.progress.gold)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white).monospacedDigit()
            }
        }
    }

    private func bottomMenu(_ state: TokegotchiState) -> some View {
        HStack(spacing: 6) {
            ForEach(Screen.allCases) { s in
                PixelIconButton(glyph: s.glyph, label: s.label, selected: screen == s) {
                    screen = s
                }
            }
            Spacer()
        }
    }

    /// Battle pop-up — auto-overlays the current screen when active, so the
    /// player can't miss that they're in a fight.
    private func battleOverlay(state: TokegotchiState, battle: ActiveBattle) -> some View {
        VStack(spacing: 4) {
            Text("⚔  BATTLE  ⚔")
                .font(.system(.caption, design: .monospaced)).fontWeight(.bold)
                .foregroundStyle(Color(red: 0.95, green: 0.85, blue: 0.30))
            ScrollView { ActiveBattleCard(gaiden: gaiden, state: state, battle: battle) }
        }
        .padding(10)
        .background(
            ZStack {
                Rectangle().fill(Color.black.opacity(0.90))
                Rectangle().stroke(Color(red: 0.95, green: 0.85, blue: 0.30), lineWidth: 2)
            }
        )
        .padding(4)
    }

    // MARK: - Screens

    private func homeScreen(_ state: TokegotchiState) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                heroCard(state)
                recentDropsCard
            }
        }
    }

    private func townScreen(_ state: TokegotchiState) -> some View {
        ScrollView { townCard(state) }
    }

    private func mapScreen(_ state: TokegotchiState) -> some View {
        RegionMapCard(gaiden: gaiden, state: state)
    }

    private func inventoryScreen(_ state: TokegotchiState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                PixelButton(label: wardrobeOpen ? "Close wardrobe" : "Wardrobe") {
                    toggleWardrobe(state)
                }
                Spacer()
            }
            if wardrobeOpen { wardrobeCarousel(state) }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    inventoryCard(state)
                    gearCard(state)
                }
            }
        }
    }

    private func hallScreen(_ state: TokegotchiState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                achievementsCard(state)
                if !state.bloodline.ancestors.isEmpty {
                    HallOfFameCard(state: state)
                }
            }
        }
    }

    private func settingsScreen(_ state: TokegotchiState) -> some View {
        ScrollView { settingsCard }
    }

    // MARK: - Gear

    @State private var gearBagPage: Int = 0
    private static let gearBagPageSize = 4

    private func gearCard(_ state: TokegotchiState) -> some View {
        let owned: [(Gear, Int)] = GearCatalog.all.compactMap { g in
            let n = state.inventory.items[g.id] ?? 0
            return n > 0 ? (g, n) : nil
        }
        let pageSize = Self.gearBagPageSize
        let totalPages = max(1, (owned.count + pageSize - 1) / pageSize)
        let clampedPage = min(gearBagPage, totalPages - 1)
        let start = clampedPage * pageSize
        let end = min(start + pageSize, owned.count)
        let pageItems = owned.isEmpty ? [] : Array(owned[start..<end])

        return Card(title: "Gear") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Gear.Slot.allCases, id: \.self) { slot in
                    let equippedId = state.inventory.equippedGear[slot.rawValue] ?? nil
                    HStack(spacing: 6) {
                        Text(slot.rawValue.capitalized).gameFont(.xsmall).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                        if let id = equippedId, let g = GearCatalog.find(id) {
                            Text("\(g.glyph) \(g.name)").gameFont(.small).lineLimit(1)
                            Spacer()
                            Text(gearStatLine(g)).gameFont(.xsmall).foregroundStyle(.tertiary).lineLimit(1)
                            PixelButton(label: "✕") {
                                Task { await gaiden.unequipGear(slot) }
                            }
                            .help("Remove")
                        } else {
                            Text("—").gameFont(.small).foregroundStyle(.tertiary)
                            Spacer()
                        }
                    }
                }
                if !owned.isEmpty {
                    Divider().padding(.vertical, 2)
                    HStack {
                        Text("Bag (\(owned.count))").gameFont(.xsmall).fontWeight(.semibold).foregroundStyle(.secondary)
                        Spacer()
                        if totalPages > 1 {
                            PixelArrowButton(direction: .left, disabled: clampedPage == 0) {
                                gearBagPage = max(0, clampedPage - 1)
                            }
                            Text("\(clampedPage + 1)/\(totalPages)").gameFont(.xsmall).monospacedDigit()
                            PixelArrowButton(direction: .right, disabled: clampedPage >= totalPages - 1) {
                                gearBagPage = min(totalPages - 1, clampedPage + 1)
                            }
                        }
                    }
                    ForEach(pageItems, id: \.0.id) { g, n in
                        HStack(spacing: 6) {
                            Text("\(g.glyph) \(g.name)").gameFont(.small).lineLimit(1)
                            if n > 1 { Text("×\(n)").gameFont(.xsmall).foregroundStyle(.secondary) }
                            Spacer()
                            Text(gearStatLine(g)).gameFont(.xsmall).foregroundStyle(.tertiary).lineLimit(1)
                            PixelButton(label: "Equip", prominent: true) {
                                Task { await gaiden.equipGear(g.id) }
                            }
                            PixelButton(label: "\(max(1, g.priceGold / 2))g") {
                                Task { await gaiden.sellGear(g.id) }
                            }
                            .help("Sell")
                        }
                    }
                }
            }
        }
    }

    private func gearStatLine(_ g: Gear) -> String {
        var parts: [String] = []
        if g.attackBonus != 0  { parts.append("ATK +\(g.attackBonus)") }
        if g.defenseBonus != 0 { parts.append("DEF +\(g.defenseBonus)") }
        if g.statBonus.str != 0 { parts.append("STR \(gearSig(g.statBonus.str))") }
        if g.statBonus.dex != 0 { parts.append("DEX \(gearSig(g.statBonus.dex))") }
        if g.statBonus.int != 0 { parts.append("INT \(gearSig(g.statBonus.int))") }
        if g.statBonus.agi != 0 { parts.append("AGI \(gearSig(g.statBonus.agi))") }
        if g.statBonus.cha != 0 { parts.append("CHA \(gearSig(g.statBonus.cha))") }
        return parts.joined(separator: " · ")
    }

    private func gearSig(_ n: Int) -> String {
        n > 0 ? "+\(n)" : "\(n)"
    }

    // MARK: - Town (NPCs, shops, trainers, quests)

    @State private var openNPCId: String?

    @ViewBuilder
    private func townCard(_ state: TokegotchiState) -> some View {
        if let region = state.world.currentRegion {
            let flavor = state.world.flavors?[region] ?? .wilderness
            let npcs = NPCRoster.npcs(for: flavor)
            Card(title: "\(region) · \(flavor.displayName) · rep \(state.world.reputation[region] ?? 0)") {
                VStack(alignment: .leading, spacing: 6) {
                    discoveryRow(state: state, region: region)
                    let steps = state.world.regionSteps?[region] ?? 0
                    let unlocked = Region.Discovery.unlocked(forSteps: steps)
                    let villageReached = unlocked.contains(.village)
                    if npcs.isEmpty {
                        Text("No one lives out here.")
                            .gameFont(.small).foregroundStyle(.secondary)
                    } else {
                        let visibleNPCs: [NPC] = villageReached ? npcs : Array(npcs.prefix(1))
                        ForEach(visibleNPCs) { npc in npcRow(state, npc: npc) }
                        if !villageReached, npcs.count > 1 {
                            Text("Trainer unlocks at \(Region.Discovery.village.rawValue) steps.")
                                .gameFont(.xsmall).foregroundStyle(.tertiary)
                        }
                    }
                    Divider().padding(.vertical, 2)
                    wanderRow(state: state, flavor: flavor)
                    dungeonRow(state: state, flavor: flavor)
                }
            }
        } else {
            Card(title: "Region") {
                Text("Send a message in Claude Code to discover your first region.")
                    .gameFont(.small).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func npcRow(_ state: TokegotchiState, npc: NPC) -> some View {
        let isOpen = openNPCId == npc.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(npc.name).gameFont(.small).fontWeight(.semibold)
                    Text(npc.title).gameFont(.xsmall).foregroundStyle(.secondary)
                }
                Spacer()
                PixelButton(label: isOpen ? "Close" : roleVerb(npc.role)) {
                    openNPCId = isOpen ? nil : npc.id
                }
            }
            if isOpen {
                Text("\"\(npc.greeting)\"")
                    .gameFont(.xsmall).foregroundStyle(.secondary).italic()
                switch npc.role {
                case let .merchant(stock): shopList(state, stock: stock)
                case let .trainer(offerings): trainerList(state, offerings: offerings)
                }
                questOfferings(state: state)
                Divider().padding(.vertical, 2)
            }
        }
    }

    private func roleVerb(_ role: NPC.Role) -> String {
        switch role {
        case .merchant: return "Shop"
        case .trainer:  return "Train"
        }
    }

    private func shopList(_ state: TokegotchiState, stock: [ShopOffer]) -> some View {
        let cha = state.vitals.stats.cha
        let haggled = NPCInteraction.haggleDiscount(cha: cha)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(stock) { offer in
                let hagPrice = NPCInteraction.haggledPrice(offer, cha: cha)
                HStack(spacing: 6) {
                    Text(ItemCatalog.label(offer.itemId)).gameFont(.small)
                    Spacer()
                    Text("\(offer.priceGold)g").gameFont(.small).monospacedDigit()
                    PixelButton(label: "Buy",
                                prominent: true,
                                disabled: state.progress.gold < offer.priceGold) {
                        Task { await gaiden.buy(from: offer) }
                    }
                    if cha > 0 {
                        PixelButton(label: "Haggle \(hagPrice)g",
                                    disabled: state.progress.gold < hagPrice) {
                            Task { await gaiden.buy(from: offer, haggle: true) }
                        }
                    }
                }
            }
            if cha > 0 {
                Text("Haggle [CHA \(cha)] — \(Int(haggled * 100))% discount")
                    .gameFont(.xsmall).foregroundStyle(.secondary)
            } else {
                Text("Train your CHA to unlock haggling.")
                    .gameFont(.xsmall).foregroundStyle(.tertiary)
            }
        }
    }

    private func trainerList(_ state: TokegotchiState, offerings: [TrainerOffering]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(offerings) { offering in
                // Skill grants are one-shot — flag and disable when already
                // learned so the player doesn't burn EXP re-buying.
                let alreadyKnown: Bool = {
                    if case let .learnSkill(skillId) = offering.effect {
                        return state.inventory.skillsLearned.contains(skillId)
                    }
                    return false
                }()
                HStack(spacing: 6) {
                    Text(offering.label).gameFont(.small)
                        .strikethrough(alreadyKnown)
                        .foregroundStyle(alreadyKnown ? .secondary : .primary)
                    Spacer()
                    if alreadyKnown {
                        Text("Learned").gameFont(.xsmall).foregroundStyle(.green)
                    } else {
                        Text("\(offering.priceExp) EXP").gameFont(.small).monospacedDigit()
                        PixelButton(label: "Train",
                                    prominent: true,
                                    disabled: state.progress.exp < offering.priceExp) {
                            Task { await gaiden.train(offering) }
                        }
                    }
                }
            }
        }
    }

    private func discoveryRow(state: TokegotchiState, region: String) -> some View {
        let steps = state.world.regionSteps?[region] ?? 0
        let next = Region.Discovery.next(forSteps: steps)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Steps explored: \(steps)")
                    .gameFont(.xsmall).foregroundStyle(.secondary)
                Spacer()
                if let n = next {
                    Text("Next: \(n.label) at \(n.rawValue)")
                        .gameFont(.xsmall).foregroundStyle(.tertiary)
                } else {
                    Text("Fully explored").gameFont(.xsmall).foregroundStyle(.tertiary)
                }
            }
            if let n = next {
                ProgressView(value: Double(min(steps, n.rawValue)), total: Double(n.rawValue))
                    .controlSize(.small)
            }
        }
    }

    /// Player-initiated random encounter — always available so the player
    /// has something to do regardless of region discovery state.
    private func wanderRow(state: TokegotchiState, flavor: Region.Flavor) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("🚶 Wander").gameFont(.small).fontWeight(.semibold)
                Text("Free random encounter.")
                    .gameFont(.xsmall).foregroundStyle(.secondary)
            }
            Spacer()
            PixelButton(label: "Go", disabled: state.activeBattle != nil) {
                Task { await gaiden.wanderForEncounter() }
            }
        }
    }

    private func dungeonRow(state: TokegotchiState, flavor: Region.Flavor) -> some View {
        let preview = EncounterEngine.choose(for: flavor, playerStats: state.vitals.stats, salt: 0, tier: .dungeon)
        let region = state.world.currentRegion ?? ""
        let steps = state.world.regionSteps?[region] ?? 0
        let unlocked = Region.Discovery.unlocked(forSteps: steps).contains(.dungeon)
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("🏰 Dungeon").gameFont(.small).fontWeight(.semibold)
                if let m = preview {
                    Text("\(m.monsterName) · ATK \(m.attack) · \(m.expReward) EXP / \(m.goldReward)g")
                        .gameFont(.xsmall).foregroundStyle(.secondary)
                } else {
                    Text("No boss here.").gameFont(.xsmall).foregroundStyle(.secondary)
                }
                if !unlocked {
                    Text("Sealed — unlocks at \(Region.Discovery.dungeon.rawValue) steps.")
                        .gameFont(.xsmall).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            PixelButton(label: "Enter", prominent: true,
                        disabled: state.activeBattle != nil || preview == nil || !unlocked) {
                Task { await gaiden.enterDungeon() }
            }
        }
    }

    @ViewBuilder
    private func questOfferings(state: TokegotchiState) -> some View {
        let flavor = state.world.flavors?[state.world.currentRegion ?? ""] ?? .wilderness
        let quests = QuestCatalog.quests(for: flavor)
        let active = QuestEngine.active(state: state)
        if !quests.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Quests").gameFont(.xsmall).foregroundStyle(.secondary).fontWeight(.semibold)
                ForEach(quests) { q in
                    questRow(state: state, quest: q, active: active.first { $0.questId == q.id })
                }
            }
        }
    }

    private func questRow(state: TokegotchiState, quest: Quest, active: QuestProgress?) -> some View {
        let isClaimed = (state.inventory.completedQuestIds ?? []).contains(quest.id)
        return HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(quest.name).gameFont(.small).fontWeight(.medium)
                    .strikethrough(isClaimed)
                Text(quest.description).gameFont(.xsmall).foregroundStyle(.secondary)
                let rewardText = "+\(quest.rewardGold)g · +\(quest.rewardExp) EXP" +
                    (quest.rewardItem.map { " · \(ItemCatalog.label($0))" } ?? "")
                Text(rewardText).gameFont(.xsmall).foregroundStyle(.tertiary)
                if let p = active, !p.completed {
                    Text("Progress: \(p.progress) / \(targetCount(quest.objective))")
                        .gameFont(.xsmall).foregroundStyle(.blue)
                }
            }
            Spacer()
            if isClaimed {
                Text("✓ Complete").gameFont(.xsmall).foregroundStyle(.green)
            } else if let p = active {
                if p.completed {
                    PixelButton(label: "Claim", prominent: true) {
                        Task { await gaiden.claimQuest(quest) }
                    }
                } else {
                    Text("Active").gameFont(.xsmall).foregroundStyle(.blue)
                }
            } else {
                PixelButton(label: "Accept") {
                    Task { await gaiden.acceptQuest(quest) }
                }
            }
        }
    }

    private func targetCount(_ obj: Quest.Objective) -> Int {
        switch obj {
        case let .toolCalls(_, count):     return count
        case let .reachStat(_, value):     return value
        case let .earnGold(amount):        return amount
        case let .defeatMonsters(count):   return count
        case let .reachReputation(amount): return amount
        }
    }

    /// Settings panel — compact picker rows. Help text lives in tooltips
    /// so the panel itself stays scroll-free.
    private var settingsCard: some View {
        Card(title: "Settings") {
            VStack(alignment: .leading, spacing: 8) {
                settingsRow(label: "Notify",
                            help: "Banner needs macOS permission. Badge shows a count in the menu bar.") {
                    Picker("", selection: Binding(
                        get: { notifier.mode },
                        set: { notifier.setMode($0) }
                    )) {
                        ForEach(NotificationMode.allCases) { m in Text(m.label).tag(m) }
                    }.labelsHidden().pickerStyle(.menu)
                }
                settingsRow(label: "CRT",
                            help: "Post-effect over the whole screen.") {
                    Picker("", selection: Binding(
                        get: { notifier.crtMode },
                        set: { notifier.setCRTMode($0) }
                    )) {
                        ForEach(CRTMode.allCases) { m in Text(m.label).tag(m) }
                    }.labelsHidden().pickerStyle(.menu)
                }
                settingsRow(label: "Combat",
                            help: "Passive auto-resolves. Active opens a turn-based modal. Auto-play forces Passive.") {
                    Picker("", selection: Binding(
                        get: { notifier.combatMode },
                        set: { notifier.setCombatMode($0) }
                    )) {
                        ForEach(CombatMode.allCases) { m in Text(m.label).tag(m) }
                    }.labelsHidden().pickerStyle(.menu)
                    .disabled(notifier.autoPlay)
                }
                settingsRow(label: "Auto-play",
                            help: "Pet eats, claims quests, buys food, and fights on its own.") {
                    Toggle("", isOn: Binding(
                        get: { notifier.autoPlay },
                        set: { notifier.setAutoPlay($0) }
                    )).labelsHidden()
                }
                Divider().padding(.vertical, 2)
                // Debug readout — surfaces the live plan signal that drives
                // aging + HP drain, so the player can see why their pet is
                // wearing down at the rate it is.
                debugPanel
                Divider().padding(.vertical, 2)
                resetTokegotchiRow
                if let onExitGame {
                    Divider().padding(.vertical, 2)
                    HStack {
                        Spacer()
                        PixelButton(label: "Exit game", size: .regular) {
                            onExitGame()
                        }
                        .help("Return to the games launcher.")
                    }
                }
            }
        }
    }

    /// Two-click reset control: the first click reveals a confirm button so
    /// destructive resets need a deliberate second tap. Mirrors the nested-
    /// menu confirmation pattern the Tokade app menu used before this moved
    /// into the game's own Settings.
    @State private var resetConfirming: Bool = false
    private var resetTokegotchiRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Reset Tokegotchi").gameFont(.small).fontWeight(.semibold)
                Text(resetConfirming
                     ? "This will erase your current pet, ancestors, and progress. Cannot be undone."
                     : "Erase the current pet and start a fresh bloodline.")
                    .gameFont(.xsmall)
                    .foregroundStyle(resetConfirming ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if resetConfirming {
                PixelButton(label: "Cancel") {
                    resetConfirming = false
                }
                PixelButton(label: "Reset") {
                    Task {
                        await gaiden.eraseHistory()
                        resetConfirming = false
                    }
                }
            } else {
                PixelButton(label: "Reset…") {
                    resetConfirming = true
                }
            }
        }
    }

    /// Debug section in Settings — shows the live plan signal so the player
    /// can see what's driving aging + HP drain. Lets us sanity-check plan
    /// normalization on Pro / Max / Max-5× without a separate tooling pass.
    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Debug").gameFont(.xsmall).foregroundStyle(.tertiary).fontWeight(.semibold)
            HStack(spacing: 12) {
                let pct = store.rateLimits?.fiveHour?.usedPercentage
                Text("5h budget: \(pct.map { String(format: "%.1f%%", $0) } ?? "—")")
                    .gameFont(.xsmall).foregroundStyle(.secondary).monospacedDigit()
                if let last = gaiden.state?.identity.lastUsedPercentage {
                    Text("Δ since last tick: \(String(format: "%.2f%%", max(0, (pct ?? 0) - last)))")
                        .gameFont(.xsmall).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if let s = gaiden.state {
                let lifePct = Int((Double(s.identity.ageTokens)
                                   / Double(max(s.identity.lifespanTokens, 1))) * 100)
                Text("Lifespan: \(lifePct)% · \(s.identity.ageTokens)/\(s.identity.lifespanTokens) age tokens")
                    .gameFont(.xsmall).foregroundStyle(.secondary).monospacedDigit()
                    .lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private func settingsRow(
        label: String, help: String, @ViewBuilder control: () -> some View
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 70, alignment: .leading)
                .gameFont(.small)
            control()
            Spacer()
        }
        .help(help)
    }

    /// Open or close the wardrobe. Opening snapshots the current outfit into
    /// `draftCosmetic` so carousel cycling previews without persisting.
    /// Closing without applying discards the draft.
    private func toggleWardrobe(_ state: TokegotchiState) {
        if wardrobeOpen {
            wardrobeOpen = false
            draftCosmetic = nil
        } else {
            draftCosmetic = state.inventory.equippedCosmetic
            wardrobeOpen = true
        }
    }

    /// Inline wardrobe section. Each slot is a left-arrow / current / right-arrow
    /// row. Selection updates `draftCosmetic` only — the sprite previews the
    /// change live, but nothing is persisted until the player taps Apply.
    private func wardrobeCarousel(_ state: TokegotchiState) -> some View {
        let owned = Set(state.inventory.discoveredCosmetics ?? CosmeticCatalog.starters.map(\.id))
        let totalCount = CosmeticCatalog.all.count
        return Card(title: "Wardrobe (\(owned.count)/\(totalCount))") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(WardrobeSlots.slots, id: \.self) { slot in
                    carouselRow(slot: slot, owned: owned)
                }
                Divider().padding(.vertical, 2)
                HStack(spacing: 6) {
                    PixelButton(label: "Apply", prominent: true, disabled: draftEqualsSaved(state)) {
                        Task { await applyDraft() }
                    }
                    PixelButton(label: "Reset", disabled: draftEqualsSaved(state)) {
                        draftCosmetic = state.inventory.equippedCosmetic
                    }
                    Spacer()
                    Text(draftEqualsSaved(state) ? "No changes" : "Unsaved")
                        .gameFont(.xsmall).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Per-slot carousel. Cycles include "—" (unequipped) + every cosmetic
    /// in that slot (owned and locked). Locked entries render as ??? with
    /// the unlock hint, and equipping is blocked.
    private func carouselRow(slot: String, owned: Set<String>) -> some View {
        let all = CosmeticCatalog.bySlot(slot)
        // Cycle order: unequipped first, then catalog order.
        let cycle: [Cosmetic?] = [nil] + all.map(Optional.some)
        let draft = draftCosmetic ?? [:]
        let currentId: String? = draft[slot] ?? nil
        let idx = cycle.firstIndex(where: { $0?.id == currentId }) ?? 0
        let current = cycle[idx]
        let isLocked = current.map { !owned.contains($0.id) } ?? false
        let label: String = {
            guard let c = current else { return "—" }
            return isLocked ? "???" : c.display
        }()
        let hint: String = current.map { CosmeticCatalog.unlockHint(for: $0) } ?? ""
        return HStack(spacing: 8) {
            Text(slot.capitalized)
                .frame(width: 56, alignment: .leading)
                .gameFont(.small)
                .foregroundStyle(.secondary)
            PixelArrowButton(direction: .left) {
                let prev = (idx - 1 + cycle.count) % cycle.count
                setDraft(slot: slot, value: cycle[prev]?.id)
            }
            // Single-line label only. The unlock hint moved out of the row
            // into the panel below the wardrobe so long sentences don't get
            // truncated mid-word inside this narrow row.
            HStack(spacing: 4) {
                if isLocked { Text("🔒").gameFont(.xsmall) }
                Text(label)
                    .gameFont(.small)
                    .foregroundStyle(isLocked ? .secondary : .primary)
            }
            .frame(maxWidth: .infinity)
            PixelArrowButton(direction: .right) {
                let next = (idx + 1) % cycle.count
                setDraft(slot: slot, value: cycle[next]?.id)
            }
            Text("\(idx + 1)/\(cycle.count)")
                .gameFont(.xsmall)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
                .monospacedDigit()
        }
        .help(isLocked ? "Locked — \(hint)" : "")
    }

    /// Panel below the wardrobe carousel that lists how to unlock any
    /// locked cosmetics the player is currently previewing. Kept out of
    /// the carousel rows because long unlock sentences ("Unlock by earning
    /// the …") used to get truncated in the narrow row.
    private func lockedHintsPanel(_ entries: [(slot: String, cos: Cosmetic)]) -> some View {
        Card(title: "Locked previews") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entries, id: \.cos.id) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("🔒").gameFont(.xsmall)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(entry.slot.capitalized) · \(entry.cos.display)")
                                .gameFont(.small).fontWeight(.semibold)
                            Text(CosmeticCatalog.unlockHint(for: entry.cos))
                                .gameFont(.xsmall).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func setDraft(slot: String, value: String?) {
        var d = draftCosmetic ?? [:]
        d[slot] = value
        draftCosmetic = d
    }

    private func draftEqualsSaved(_ state: TokegotchiState) -> Bool {
        guard let d = draftCosmetic else { return true }
        // Both directions — saved has all slots, draft may or may not.
        for (k, v) in state.inventory.equippedCosmetic {
            if (d[k] ?? nil) != v { return false }
        }
        for (k, v) in d {
            if (state.inventory.equippedCosmetic[k] ?? nil) != v { return false }
        }
        return true
    }

    /// Commit each slot in the draft to the saved state. Locked cosmetics
    /// can't be worn — if the draft slot points at a locked id, the slot
    /// is explicitly unequipped instead. This also clears out legacy
    /// equips on pets that predate the cosmetic catalog (e.g., a pre-1.x
    /// wizard-hat that's no longer in `discoveredCosmetics`).
    private func applyDraft() async {
        guard let d = draftCosmetic, let s = gaiden.state else { return }
        let owned = Set(s.inventory.discoveredCosmetics ?? CosmeticCatalog.starters.map(\.id))
        for (slot, value) in d {
            if let v = value, !owned.contains(v) {
                // Locked id in the draft — persist as unequipped so the
                // pet doesn't keep wearing a cosmetic it doesn't own.
                await gaiden.equipCosmetic(slot: slot, name: nil)
            } else {
                await gaiden.equipCosmetic(slot: slot, name: value)
            }
        }
        // Reset the draft to the (now-clean) saved state so the carousel
        // doesn't keep showing a locked preview after Apply.
        draftCosmetic = gaiden.state?.inventory.equippedCosmetic
    }

    @State private var inventoryPage: Int = 0
    private static let inventoryPageSize = 5

    private func inventoryCard(_ state: TokegotchiState) -> some View {
        let entries: [(ItemDef, Int)] = ItemCatalog.all.compactMap { def in
            let count = state.inventory.items[def.id] ?? 0
            return count > 0 ? (def, count) : nil
        }
        let pageSize = Self.inventoryPageSize
        let pageCount = max(1, (entries.count + pageSize - 1) / pageSize)
        let safePage = min(inventoryPage, pageCount - 1)
        let startIdx = safePage * pageSize
        let endIdx = min(entries.count, startIdx + pageSize)
        let pageEntries = entries.isEmpty ? [] : Array(entries[startIdx..<endIdx])
        return Card(title: "Inventory (\(entries.count))") {
            if entries.isEmpty {
                Text("Empty. Use Claude Code — items drop from tool calls and edits.")
                    .gameFont(.small).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(pageEntries, id: \.0.id) { def, count in
                        itemRow(def: def, count: count)
                    }
                    if pageCount > 1 {
                        HStack(spacing: 6) {
                            PixelArrowButton(direction: .left, disabled: safePage == 0) {
                                inventoryPage = max(0, safePage - 1)
                            }
                            Text("\(safePage + 1)/\(pageCount)")
                                .gameFont(.xsmall).foregroundStyle(.secondary).monospacedDigit()
                            PixelArrowButton(direction: .right, disabled: safePage >= pageCount - 1) {
                                inventoryPage = min(pageCount - 1, safePage + 1)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func itemRow(def: ItemDef, count: Int) -> some View {
        let sellValue = ItemCatalog.sellValue(def.id)
        return HStack(spacing: 6) {
            Text("\(def.glyph) \(def.display) × \(count)").gameFont(.small)
            Spacer()
            Text(effectDescription(def)).gameFont(.xsmall).foregroundStyle(.secondary)
            PixelButton(label: "Use", prominent: true) {
                Task { await gaiden.useItem(def.id) }
            }
            if sellValue > 0 {
                PixelButton(label: "\(sellValue)g") {
                    Task { await gaiden.sellItem(def.id) }
                }
                .help("Sell")
            }
            PixelButton(label: "✕") {
                Task { await gaiden.dropItem(def.id) }
            }
            .help("Drop")
        }
    }

    private func effectDescription(_ def: ItemDef) -> String {
        switch def.kind {
        case let .food(hp):           return "+\(hp) HP"
        case let .spPotion(sp):       return "+\(sp) SP"
        case let .statBoost(s, d):    return "+\(d) \(s)"
        case let .scrap(g):           return "Sell for \(g)g"
        case .keyItem:                return "Key item"
        }
    }

    private func achievementsCard(_ state: TokegotchiState) -> some View {
        let earned: [Achievement] = AchievementCatalog.all.filter { ach in
            (state.inventory.items[AchievementCatalog.inventoryPrefix + ach.id] ?? 0) > 0
        }
        return Card(title: "Achievements (\(earned.count) / \(AchievementCatalog.all.count))") {
            if earned.isEmpty {
                Text("None yet. Achievements fire automatically as you play.")
                    .gameFont(.small).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(earned, id: \.id) { a in
                        HStack {
                            Text("🏅 \(a.title)").gameFont(.small)
                            Spacer()
                            Text(a.description).gameFont(.xsmall).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func heroCard(_ state: TokegotchiState) -> some View {
        // HP/SP/EXP/gold already shown in the top resource bar — Profile
        // focuses on identity, stats, and the live sprite preview.
        Card {
            HStack(alignment: .top, spacing: 12) {
                // Profile always renders the SAVED outfit, never the
                // wardrobe draft — otherwise a locked cosmetic the player
                // cycled past in the wardrobe (without applying) would
                // leak into other tabs as if it were equipped.
                let outfit = state.inventory.equippedCosmetic
                SpriteView(
                    frames: BundledSprites.compose(
                        frames: BundledSprites.breathingCycle,
                        equipped: outfit
                    ),
                    palette: Palette.from(
                        skin: state.identity.appearance.skinSwatch,
                        iris: state.identity.appearance.irisSwatch,
                        hair: state.identity.appearance.hairSwatch
                    ),
                    scale: 4,
                    fps: 4,
                    crt: .off
                )
                .frame(width: 128, height: 216)
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.identity.name)
                        .font(.system(.title3, design: .monospaced)).fontWeight(.semibold)
                    // Lead with wall-clock age (most intuitive) at the
                    // largest meaningful unit, then a token-age line for
                    // those who care about lifespan progress.
                    let pct = Int((Double(state.identity.ageTokens)
                                   / Double(max(state.identity.lifespanTokens, 1))) * 100)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text("Gen \(state.identity.generation) · \(liveAge(from: state.identity.bornAt, now: ctx.date)) old")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Text("\(ageShort(state.identity.ageTokens)) / \(ageShort(state.identity.lifespanTokens)) age tokens · life \(pct)%")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                    if let region = state.world.currentRegion {
                        let flavor = state.world.flavors?[region]
                        let rep = state.world.reputation[region] ?? 0
                        Text("\(flavor?.displayName ?? "Wilderness") · rep \(rep)")
                            .gameFont(.xsmall).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer().frame(height: 2)
                    statsLine(state.vitals.stats)
                    if state.isCritical {
                        Text("CRITICAL — feed or use Revive Stone")
                            .gameFont(.xsmall).foregroundStyle(.red).fontWeight(.semibold)
                    }
                }
            }
        }
    }

    /// Compact age display — 12_345_678 → "12.3M" so the line doesn't wrap.
    private func ageShort(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1000     { return String(format: "%.0fK", Double(n) / 1000) }
        return "\(n)"
    }

    /// Wall-clock age formatted as "Xd Yh Zm Ws" with whichever leading
    /// units are zero collapsed. Updates every second via TimelineView.
    private func liveAge(from born: Date, now: Date) -> String {
        let secs = max(0, Int(now.timeIntervalSince(born)))
        let d = secs / 86400
        let h = (secs % 86400) / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if d > 0 { return String(format: "%dd %02dh %02dm %02ds", d, h, m, s) }
        if h > 0 { return String(format: "%dh %02dm %02ds", h, m, s) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return String(format: "%ds", s)
    }

    private func vitalsBar(label: String, value: Int, total: Int, tint: Color) -> some View {
        let denom = max(total, 1)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).gameFont(.small).foregroundStyle(.secondary)
                Spacer()
                Text("\(value)/\(total)").gameFont(.small).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: Double(max(value, 0)), total: Double(denom))
                .tint(tint)
        }
    }

    private func statsLine(_ s: TokegotchiState.Stats) -> some View {
        HStack(spacing: 12) {
            stat("STR", s.str)
            stat("DEX", s.dex)
            stat("INT", s.int)
            stat("AGI", s.agi)
            stat("CHA", s.cha)
        }
    }

    private func stat(_ name: String, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(value)").gameFont(.small).monospacedDigit().fontWeight(.semibold)
            Text(name).gameFont(.xsmall).foregroundStyle(.secondary)
        }
    }

    private var recentDropsCard: some View {
        Card(title: "Recent drops") {
            if gaiden.lastResults.isEmpty {
                Text("No telemetry yet. Use Claude Code to drop items.")
                    .gameFont(.small).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(gaiden.lastResults.suffix(8).enumerated()), id: \.offset) { _, r in
                        Text(prettyResult(r)).gameFont(.small).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func prettyResult(_ r: TickResult) -> String {
        switch r {
        case let .itemDropped(id, count): return "+ \(count) × \(ItemCatalog.label(id))"
        case let .hpChanged(d): return "HP \(d >= 0 ? "+" : "")\(d)"
        case let .spChanged(d): return "SP \(d >= 0 ? "+" : "")\(d)"
        case let .ageAdvanced(p, model): return "aged +\(p) (\(model))"
        case let .statBoost(stat, d): return "\(stat) +\(d)"
        case .enteredCritical: return "entered CRITICAL"
        case let .died(cause): return "died (\(cause.rawValue))"
        case let .encounter(name, outcome):
            switch outcome {
            case let .victory(exp, gold): return "⚔️ defeated \(name) (+\(exp) EXP, +\(gold)g)"
            case .fled: return "🏃 fled from \(name)"
            }
        case let .achievementEarned(id): return "🏅 \(AchievementCatalog.byId[id]?.title ?? id)"
        }
    }
}

// MARK: - Wardrobe

/// The cosmetic slots that are actually bundled (matrices baked) at v1.
/// Hardcoded-color cosmetics from the design folder need to be reworked to
/// use palette placeholders before they can be added here.
enum WardrobeSlots {
    /// Slot identifiers in the order they should appear in the wardrobe.
    /// Matches CosmeticCatalog.slotOrder.
    static let slots: [String] = CosmeticCatalog.slotOrder
}

// MARK: - Death screen

/// Shown when the current Tokegotchi has a non-nil `deathState`. Eulogy + key
/// stats + a "Hatch next generation" button that opens the character creator
/// with the inheritance flow.
@MainActor
struct DeathScreen: View {
    @Bindable var gaiden: TokenGaidenStore
    let dead: TokegotchiState
    var notifier: Notifier?
    @State private var creatingNext = false

    var body: some View {
        if creatingNext {
            CharacterCreator(gaiden: gaiden, notifier: notifier, inheritFrom: dead)
        } else {
            Card(title: "🪦 In memoriam") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 16) {
                        // Faded final portrait of the deceased.
                        SpriteView(
                            frames: BundledSprites.compose(
                                frames: ["idle"],
                                equipped: dead.inventory.equippedCosmetic
                            ),
                            palette: Palette.from(
                                skin: dead.identity.appearance.skinSwatch,
                                iris: dead.identity.appearance.irisSwatch,
                                hair: dead.identity.appearance.hairSwatch
                            ),
                            scale: 4,
                            fps: 1,
                            crt: .off
                        )
                        .frame(width: 128, height: 216)
                        .opacity(0.55)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(dead.identity.name).font(.system(.title3, design: .monospaced)).fontWeight(.semibold)
                            Text("Generation \(dead.identity.generation)")
                                .gameFont(.small).foregroundStyle(.secondary)
                            Text(eulogyLine).gameFont(.small).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer().frame(height: 4)
                            statLine
                            Spacer().frame(height: 4)
                            PixelButton(label: "Hatch next generation", prominent: true) {
                                creatingNext = true
                            }
                        }
                    }
                    Text("30% of peak stats, 100% of reputation, all items, equipped cosmetics, and 10% of gold carry forward.")
                        .gameFont(.xsmall).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var eulogyLine: String {
        guard let d = dead.deathState else { return "" }
        switch d.cause {
        case .natural: return "Lived a full life, retiring peacefully after \(d.daysLived) day(s) of service."
        case .hpZero:  return "Fell in the line of duty after \(d.daysLived) day(s)."
        }
    }

    private var statLine: some View {
        guard let d = dead.deathState else { return AnyView(EmptyView()) }
        let s = d.peakStats
        return AnyView(
            HStack(spacing: 10) {
                stat("STR", s.str); stat("DEX", s.dex); stat("INT", s.int); stat("AGI", s.agi); stat("CHA", s.cha)
            }
        )
    }

    private func stat(_ name: String, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(value)").gameFont(.small).monospacedDigit().fontWeight(.semibold)
            Text(name).gameFont(.xsmall).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Hall of Fame

/// Compact list of past generations on the bloodline. Embedded in the alive
/// layout when expanded.
@MainActor
struct HallOfFameCard: View {
    let state: TokegotchiState

    var body: some View {
        Card(title: "Hall of Fame (\(state.bloodline.ancestors.count))") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(state.bloodline.ancestors.reversed().enumerated()), id: \.offset) { _, a in
                    HStack {
                        Text("Gen \(a.generation) · \(a.name)").gameFont(.small).fontWeight(.medium)
                        Spacer()
                        Text("\(a.daysLived)d · \(a.causeOfDeath.rawValue)")
                            .gameFont(.xsmall).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Character creator

@MainActor
struct CharacterCreator: View {
    @Bindable var gaiden: TokenGaidenStore
    var notifier: Notifier?
    /// If non-nil, this pet died and the next-gen hatch should inherit. We
    /// keep the dead pet's reference so we can call hatchNextGeneration().
    let inheritFrom: TokegotchiState?
    @State private var name: String
    @State private var skinIdx: Int = 0
    @State private var irisIdx: Int = 0
    @State private var hairColorIdx: Int = 0
    @State private var hairStyleIdx: Int = 0
    @State private var autoPlayChoice: Bool

    init(gaiden: TokenGaidenStore, notifier: Notifier? = nil, inheritFrom: TokegotchiState? = nil) {
        self.gaiden = gaiden
        self.notifier = notifier
        self.inheritFrom = inheritFrom
        self._autoPlayChoice = State(initialValue: notifier?.autoPlay ?? false)
        // Default name follows the bloodline numerals (Boba II, Boba III…) if
        // we're inheriting, otherwise a clean "Boba".
        if let parent = inheritFrom {
            let nextGen = parent.identity.generation + 1
            let suffix = Self.romanNumeral(nextGen)
            self._name = State(initialValue: "\(parent.identity.name) \(suffix)")
        } else {
            self._name = State(initialValue: "Boba")
        }
    }

    private static func romanNumeral(_ n: Int) -> String {
        let table: [(Int, String)] = [
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
        ]
        var n = n
        var result = ""
        for (v, s) in table { while n >= v { result += s; n -= v } }
        return result.isEmpty ? "I" : result
    }

    var body: some View {
        Card(title: inheritFrom == nil ? "Welcome to Token Gaiden" : "Hatch the next generation") {
            VStack(alignment: .leading, spacing: 14) {
                if let parent = inheritFrom {
                    Text("Successor to \(parent.identity.name). Inherits 30% of peak stats, all items, equipped cosmetics, town reputation, and 10% of gold.")
                        .gameFont(.small).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Hatch your first Tokegotchi. It will live and grow based on how you use Claude Code.")
                        .gameFont(.small).foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 16) {
                    previewSprite
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Name").frame(width: 80, alignment: .leading).gameFont(.small)
                            TextField("name", text: $name).textFieldStyle(.roundedBorder)
                        }
                        carouselRow(
                            label: "Skin",
                            index: $skinIdx,
                            names: CharacterCreatorSwatches.skin.map(\.name)
                        )
                        carouselRow(
                            label: "Iris",
                            index: $irisIdx,
                            names: CharacterCreatorSwatches.iris.map(\.name)
                        )
                        carouselRow(
                            label: "Hair color",
                            index: $hairColorIdx,
                            names: CharacterCreatorSwatches.hair.map(\.name)
                        )
                        carouselRow(
                            label: "Hair style",
                            index: $hairStyleIdx,
                            names: CharacterCreatorSwatches.hairStyles
                        )
                    }
                }

                Divider()
                HStack(alignment: .top, spacing: 8) {
                    Text("Auto-play").frame(width: 80, alignment: .leading).gameFont(.small)
                    Toggle("", isOn: $autoPlayChoice).labelsHidden()
                    Text(autoPlayChoice ? "On" : "Off").gameFont(.xsmall).foregroundStyle(.secondary)
                    Spacer()
                }
                Text(autoPlayChoice
                     ? "Pet will heal, claim quests, and fight on its own. You can change this later in Menu → SETTINGS."
                     : "You'll control feeding, combat, and questing manually. Toggle anytime in Menu → SETTINGS.")
                    .gameFont(.xsmall).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                PixelButton(
                    label: inheritFrom == nil ? "Hatch" : "Hatch next generation",
                    size: .regular,
                    prominent: true,
                    disabled: name.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    Task { await hatch() }
                }
            }
        }
    }

    /// Carousel row that matches the Wardrobe UI: < current N/M >. Wraps around.
    private func carouselRow(label: String, index: Binding<Int>, names: [String]) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 80, alignment: .leading)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            PixelArrowButton(direction: .left) {
                index.wrappedValue = (index.wrappedValue - 1 + names.count) % names.count
            }
            Text(names[index.wrappedValue])
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            PixelArrowButton(direction: .right) {
                index.wrappedValue = (index.wrappedValue + 1) % names.count
            }
            Text("\(index.wrappedValue + 1)/\(names.count)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
                .monospacedDigit()
        }
    }

    /// Live preview using the same composition pipeline as the alive view.
    /// Uses the default starter outfit (tunic + long-pants + leather belt) so
    /// the player sees the actual look they'll get after hatching.
    private var previewSprite: some View {
        let outfit: [String: String?] = [
            "hair":  CharacterCreatorSwatches.hairStyles[hairStyleIdx],
            "shirt": "tunic",
            "pants": "long-pants",
            "belt":  "leather",
        ]
        let palette = Palette.from(
            skin: CharacterCreatorSwatches.skin[skinIdx].name,
            iris: CharacterCreatorSwatches.iris[irisIdx].name,
            hair: CharacterCreatorSwatches.hair[hairColorIdx].name
        )
        return SpriteView(
            frames: BundledSprites.compose(
                frames: BundledSprites.breathingCycle,
                equipped: outfit
            ),
            palette: palette,
            scale: 4,
            fps: 4,
            crt: .off
        )
        .frame(width: 128, height: 216)
    }

    private func hatch() async {
        let appearance = TokegotchiState.Appearance(
            skinSwatch:  CharacterCreatorSwatches.skin[skinIdx].name,
            irisSwatch:  CharacterCreatorSwatches.iris[irisIdx].name,
            hairStyle:   CharacterCreatorSwatches.hairStyles[hairStyleIdx],
            hairSwatch:  CharacterCreatorSwatches.hair[hairColorIdx].name
        )
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        notifier?.setAutoPlay(autoPlayChoice)
        if inheritFrom != nil {
            await gaiden.hatchNextGeneration(name: trimmed, appearance: appearance)
        } else {
            await gaiden.startNewLineage(name: trimmed, appearance: appearance)
        }
    }
}
