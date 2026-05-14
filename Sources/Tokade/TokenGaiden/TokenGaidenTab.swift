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
    }

    // MARK: - Alive layout

    private func aliveLayout(_ state: TokegotchiState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            heroCard(state)
            recentDropsCard
        }
    }

    private func heroCard(_ state: TokegotchiState) -> some View {
        Card {
            HStack(alignment: .top, spacing: 16) {
                SpriteView(
                    frames: BundledSprites.breathing,
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
                        Text("Region: \(region)").font(.caption2).foregroundStyle(.secondary)
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
        case let .itemDropped(id, count): return "+ \(count) × \(id)"
        case let .hpChanged(d): return "HP \(d >= 0 ? "+" : "")\(d)"
        case let .spChanged(d): return "SP \(d >= 0 ? "+" : "")\(d)"
        case let .ageAdvanced(p, model): return "aged +\(p) (\(model))"
        case let .statBoost(stat, d): return "\(stat) +\(d)"
        case .enteredCritical: return "entered CRITICAL"
        case let .died(cause): return "died (\(cause.rawValue))"
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
