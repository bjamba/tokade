import SwiftUI

/// Turn-based combat panel shown when `state.activeBattle != nil` and combat
/// mode is set to Active. Three buttons (Attack / Item / Run) plus a log of
/// the last few exchanges. Survives panel re-opens because the battle is
/// persisted into the Tokegotchi state.
@MainActor
struct ActiveBattleCard: View {
    @Bindable var gaiden: TokenGaidenStore
    let state: TokegotchiState
    let battle: ActiveBattle
    @State private var showingItemPicker = false

    var body: some View {
        Card(title: "⚔️ Battle · \(battle.monsterName)") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    enemyView
                    Spacer()
                    playerView
                }
                logView
                if let outcome = battle.resolvedOutcome {
                    outcomeDialog(outcome)
                } else if showingItemPicker {
                    itemPicker
                } else if showingSkillPicker {
                    skillPicker
                } else {
                    actionRow
                }
            }
        }
    }

    /// Post-fight dialog. Shown after victory / flee / defeat. Player must
    /// press Continue to clear it.
    private func outcomeDialog(_ outcome: ActiveBattle.ResolvedOutcome) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch outcome {
            case .victory:
                Text("✨  VICTORY!  ✨")
                    .font(.system(.title3, design: .monospaced)).fontWeight(.bold)
                    .foregroundStyle(Color(red: 0.95, green: 0.85, blue: 0.30))
                Text("Defeated \(battle.monsterName).")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.white)
                Text("+\(battle.monsterExpReward) EXP   +\(battle.monsterGoldReward) GOLD")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(GamePalette.exp)
            case .fled:
                Text("ESCAPED")
                    .font(.system(.title3, design: .monospaced)).fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("You slipped away from \(battle.monsterName). No rewards.")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.gray)
            case .playerDown:
                Text("DEFEATED")
                    .font(.system(.title3, design: .monospaced)).fontWeight(.bold)
                    .foregroundStyle(GamePalette.hp)
                Text("\(state.identity.name) is knocked out. Use a Revive Stone or food to recover.")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                PixelButton(label: "Continue", size: .regular, prominent: true) {
                    Task { await gaiden.dismissBattleOutcome() }
                }
            }
        }
    }

    private var enemyView: some View {
        HStack(alignment: .top, spacing: 8) {
            if let sprite = MonsterArt.sprite(for: battle.monsterName) {
                SpriteView(
                    frames: [sprite],
                    palette: MonsterArt.palette(for: battle.monsterName),
                    scale: 3,
                    fps: 0
                )
                .frame(width: 96, height: 96)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(battle.monsterName).gameFont(.small).fontWeight(.semibold)
                Text("ATK \(battle.monsterAttack) · DEF \(battle.monsterDefense)")
                    .gameFont(.xsmall).foregroundStyle(.secondary)
                PixelBar(value: battle.monsterHP, max: battle.monsterMaxHP,
                         color: GamePalette.hp, width: 120)
                Text("\(battle.monsterHP) / \(battle.monsterMaxHP) HP")
                    .gameFont(.xsmall).monospacedDigit()
            }
        }
    }

    private var playerView: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(state.identity.name).gameFont(.small).fontWeight(.semibold)
            let eff = state.effectiveStats
            Text("ATK \(eff.str + eff.dex / 2 + state.gearAttackBonus) · DEF \(eff.dex / 2 + state.gearDefenseBonus)")
                .gameFont(.xsmall).foregroundStyle(.secondary)
            PixelBar(value: state.vitals.hp, max: state.vitals.hpMax,
                     color: GamePalette.hp, width: 120)
            Text("\(state.vitals.hp) / \(state.vitals.hpMax) HP")
                .gameFont(.xsmall).monospacedDigit()
            PixelBar(value: state.vitals.sp, max: state.vitals.spMax,
                     color: GamePalette.sp, width: 120)
            Text("\(state.vitals.sp) / \(state.vitals.spMax) SP")
                .gameFont(.xsmall).monospacedDigit()
        }
    }

    private var logView: some View {
        PixelTextFrame(height: 80) {
            VStack(alignment: .leading, spacing: 1) {
                Spacer(minLength: 0)
                ForEach(battle.log.suffix(4), id: \.self) { line in
                    Text(line)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @State private var showingSkillPicker = false

    private var actionRow: some View {
        HStack(spacing: 6) {
            PixelButton(label: "Attack", size: .regular, prominent: true) {
                Task { await gaiden.combatAttack() }
            }
            PixelButton(label: "Skill", size: .regular, disabled: learnedSkills.isEmpty) {
                showingSkillPicker = true
            }
            PixelButton(label: "Item", size: .regular, disabled: usableItems.isEmpty) {
                showingItemPicker = true
            }
            PixelButton(label: "Run", size: .regular) {
                Task { await gaiden.combatFlee() }
            }
            Spacer()
        }
    }

    private var learnedSkills: [Skill] {
        state.inventory.skillsLearned.compactMap { SkillCatalog.find($0) }
    }

    private var skillPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cast which skill?").gameFont(.xsmall).foregroundStyle(.secondary)
            ForEach(learnedSkills, id: \.id) { skill in
                HStack {
                    Text("\(skill.glyph) \(skill.name)").gameFont(.small)
                    Spacer()
                    Text("\(skill.spCost) SP").gameFont(.xsmall).foregroundStyle(.secondary)
                    PixelButton(label: "Cast", prominent: true,
                                disabled: state.vitals.sp < skill.spCost) {
                        showingSkillPicker = false
                        Task { await gaiden.combatCastSkill(skill.id) }
                    }
                }
            }
            HStack {
                Spacer()
                PixelButton(label: "Cancel") { showingSkillPicker = false }
            }
        }
    }

    private var usableItems: [(ItemDef, Int)] {
        ItemCatalog.all.compactMap { def in
            let count = state.inventory.items[def.id] ?? 0
            guard count > 0 else { return nil }
            switch def.kind {
            case .food, .spPotion: return (def, count)
            default: return nil
            }
        }
    }

    private var itemPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Use which item?").gameFont(.xsmall).foregroundStyle(.secondary)
            ForEach(usableItems, id: \.0.id) { def, count in
                HStack {
                    Text("\(def.glyph) \(def.display) × \(count)").gameFont(.small)
                    Spacer()
                    PixelButton(label: "Use", prominent: true) {
                        showingItemPicker = false
                        Task { await gaiden.combatUseItem(def.id) }
                    }
                }
            }
            HStack {
                Spacer()
                PixelButton(label: "Cancel") { showingItemPicker = false }
            }
        }
    }
}
