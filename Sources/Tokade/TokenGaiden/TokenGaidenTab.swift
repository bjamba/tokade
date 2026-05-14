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
    @State private var showingWardrobe = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let state = gaiden.state {
                aliveLayout(state)
            } else {
                CharacterCreator(gaiden: gaiden)
            }
        }
        .task {
            // Apply any telemetry that arrived before we loaded.
            await gaiden.tick(against: store.events)
        }
        .onChange(of: store.events.count) { _, _ in
            Task { await gaiden.tick(against: store.events) }
        }
        .sheet(isPresented: $showingWardrobe) {
            WardrobeSheet(gaiden: gaiden, isPresented: $showingWardrobe)
        }
    }

    // MARK: - Alive layout

    private func aliveLayout(_ state: TokegotchiState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            heroCard(state)
            HStack {
                Button("Wardrobe…") { showingWardrobe = true }
                Spacer()
                Text("EXP \(state.progress.exp) · 🪙 \(state.progress.gold)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            inventoryCard(state)
            achievementsCard(state)
            recentDropsCard
        }
    }

    private func inventoryCard(_ state: TokegotchiState) -> some View {
        Card(title: "Inventory") {
            let entries: [(ItemDef, Int)] = ItemCatalog.all.compactMap { def in
                let count = state.inventory.items[def.id] ?? 0
                return count > 0 ? (def, count) : nil
            }
            if entries.isEmpty {
                Text("Empty. Use Claude Code — items drop from tool calls and edits.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entries, id: \.0.id) { def, count in
                        HStack {
                            Text("\(def.glyph) \(def.display) × \(count)")
                                .font(.caption)
                            Spacer()
                            Text(effectDescription(def)).font(.caption2).foregroundStyle(.secondary)
                            Button("Use") {
                                Task { await gaiden.useItem(def.id) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
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
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(earned, id: \.id) { a in
                        HStack {
                            Text("🏅 \(a.title)").font(.caption)
                            Spacer()
                            Text(a.description).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func heroCard(_ state: TokegotchiState) -> some View {
        Card {
            HStack(alignment: .top, spacing: 16) {
                SpriteView(
                    frames: BundledSprites.compose(
                        base: BundledSprites.breathing,
                        equipped: state.inventory.equippedCosmetic
                    ),
                    palette: .boba,
                    scale: 5,
                    fps: 3
                )
                .frame(width: 160, height: 270)
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.identity.name)
                        .font(.title3).fontWeight(.semibold)
                    Text("Gen \(state.identity.generation) · age \(state.identity.ageTokens)/\(state.identity.lifespanTokens)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let region = state.world.currentRegion {
                        let flavor = state.world.flavors?[region]
                        let rep = state.world.reputation[region] ?? 0
                        Text("Region: \(region) · \(flavor?.displayName ?? "Wilderness") · rep \(rep)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer().frame(height: 4)
                    vitalsBar(label: "HP", value: state.vitals.hp, total: state.vitals.hpMax, tint: .red)
                    vitalsBar(label: "SP", value: state.vitals.sp, total: state.vitals.spMax, tint: .blue)
                    Spacer().frame(height: 4)
                    statsLine(state.vitals.stats)
                    if state.isCritical {
                        Text("CRITICAL — feed the pet or use a Revive Stone")
                            .font(.caption).foregroundStyle(.red).fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func vitalsBar(label: String, value: Int, total: Int, tint: Color) -> some View {
        let denom = max(total, 1)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(value)/\(total)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
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
            Text("\(value)").font(.caption).monospacedDigit().fontWeight(.semibold)
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var recentDropsCard: some View {
        Card(title: "Recent drops") {
            if gaiden.lastResults.isEmpty {
                Text("No telemetry yet. Use Claude Code to drop items.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(gaiden.lastResults.suffix(8).enumerated()), id: \.offset) { _, r in
                        Text(prettyResult(r)).font(.caption).foregroundStyle(.secondary)
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

/// Sheet that lets the player swap each cosmetic slot from the v1 baked
/// inventory. Picks persist to disk immediately. Items the player hasn't
/// "owned" yet are still shown — the inventory-gating layer comes in a
/// later PR once monsters/shops drop equipment.
@MainActor
struct WardrobeSheet: View {
    @Bindable var gaiden: TokenGaidenStore
    @Binding var isPresented: Bool

    /// The cosmetics actually bundled into the app at v1. Slots not in this
    /// list aren't yet swappable.
    static let available: [(slot: String, names: [String])] = [
        ("hair",  ["horns", "spiky", "cat-ears", "pigtails", "mohawk", "antennae", "long"]),
        ("shirt", ["tunic"]),
        ("pants", ["long-pants", "shorts"]),
        ("belt",  ["leather"]),
        ("hat",   ["beanie", "wizard-hat", "cap"]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wardrobe").font(.title3).fontWeight(.semibold)
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            ForEach(Self.available, id: \.slot) { entry in
                slotRow(slot: entry.slot, options: entry.names)
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 360, height: 320)
    }

    private func slotRow(slot: String, options: [String]) -> some View {
        let current = gaiden.state?.inventory.equippedCosmetic[slot] ?? nil
        return HStack {
            Text(slot.capitalized).frame(width: 70, alignment: .leading).font(.caption)
            Picker("", selection: Binding(
                get: { current ?? "—" },
                set: { newValue in
                    let stripped = (newValue == "—") ? nil : newValue
                    Task { await gaiden.equipCosmetic(slot: slot, name: stripped) }
                }
            )) {
                Text("—").tag("—")
                ForEach(options, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

// MARK: - Character creator

@MainActor
struct CharacterCreator: View {
    @Bindable var gaiden: TokenGaidenStore
    @State private var name = "Boba"
    @State private var skinIdx = 0
    @State private var irisIdx = 0
    @State private var hairColorIdx = 0
    @State private var hairStyleIdx = 0

    var body: some View {
        Card(title: "Welcome to Token Gaiden") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Hatch your first Tokegotchi. It will live and grow based on how you use Claude Code.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Name").frame(width: 70, alignment: .leading).font(.caption)
                    TextField("name", text: $name).textFieldStyle(.roundedBorder)
                }
                pickerRow(label: "Skin", count: CharacterCreatorSwatches.skin.count, index: $skinIdx,
                          names: CharacterCreatorSwatches.skin.map(\.name))
                pickerRow(label: "Iris", count: CharacterCreatorSwatches.iris.count, index: $irisIdx,
                          names: CharacterCreatorSwatches.iris.map(\.name))
                pickerRow(label: "Hair color", count: CharacterCreatorSwatches.hair.count, index: $hairColorIdx,
                          names: CharacterCreatorSwatches.hair.map(\.name))
                pickerRow(label: "Hair style", count: CharacterCreatorSwatches.hairStyles.count, index: $hairStyleIdx,
                          names: CharacterCreatorSwatches.hairStyles)
                Button("Hatch") {
                    Task { await hatch() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func pickerRow(label: String, count: Int, index: Binding<Int>, names: [String]) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 70, alignment: .leading).font(.caption)
            Picker("", selection: index) {
                ForEach(0..<count, id: \.self) { i in
                    Text(names[i]).tag(i)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func hatch() async {
        let appearance = TokegotchiState.Appearance(
            skinSwatch:  CharacterCreatorSwatches.skin[skinIdx].name,
            irisSwatch:  CharacterCreatorSwatches.iris[irisIdx].name,
            hairStyle:   CharacterCreatorSwatches.hairStyles[hairStyleIdx],
            hairSwatch:  CharacterCreatorSwatches.hair[hairColorIdx].name
        )
        await gaiden.startNewLineage(
            name: name.trimmingCharacters(in: .whitespaces),
            appearance: appearance
        )
    }
}
