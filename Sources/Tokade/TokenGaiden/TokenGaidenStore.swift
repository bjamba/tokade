import Foundation
import Observation
import os.log

/// Owns the live Tokegotchi state and the index of which UsageEvents we've
/// already accounted for. Bridges `UsageStore` (telemetry) into Token Gaiden
/// (game effects). Sibling of `UsageStore` — both held by `TokadeApp`.
@MainActor
@Observable
final class TokenGaidenStore {
    private(set) var state: TokegotchiState?
    private(set) var lastResults: [TickResult] = []
    /// Stable identity for each event we've consumed, so we don't double-count
    /// when the JSONL is re-read. Keyed by `(messageId ?? "", timestamp)`.
    private var accountedTokens: [String: Int] = [:]

    private let save = TokegotchiSave()
    private let log = Logger(subsystem: "com.bjamba.tokade", category: "TokenGaiden")

    // MARK: - Lifecycle

    /// Load the persisted state, or leave `state == nil` (caller should show
    /// the character creator in that case).
    func load() async {
        state = await save.read()
    }

    /// Start a new bloodline. Called from the character creator on first run
    /// or after a permanent death.
    func startNewLineage(name: String, appearance: TokegotchiState.Appearance) async {
        let pet = TokegotchiState.newStarter(name: name, appearance: appearance)
        state = pet
        accountedTokens.removeAll()
        await save.write(pet)
    }

    /// Erase the save file and reset in-memory state. Wired into the existing
    /// "Erase history…" flow in `MenuView`.
    func eraseHistory() async {
        await save.erase()
        state = nil
        accountedTokens.removeAll()
        lastResults = []
    }

    /// Equip (or unequip — pass nil) a single cosmetic slot. Persists. Used by
    /// the Wardrobe UI.
    func equipCosmetic(slot: String, name: String?) async {
        guard var current = state else { return }
        current.inventory.equippedCosmetic[slot] = name
        state = current
        await save.write(current)
    }

    /// Consume one of `itemId` from the inventory and apply its effect. The
    /// effect is recorded in `lastResults` for UI feedback.
    func useItem(_ itemId: String) async {
        guard let current = state else { return }
        let (next, result) = ItemUsage.use(itemId, state: current)
        guard next != current else { return }
        state = next
        switch result {
        case let .healed(hp):
            lastResults = [.hpChanged(delta: hp)]
        case let .restoredSP(sp):
            lastResults = [.spChanged(delta: sp)]
        case let .statRaised(stat, delta):
            lastResults = [.statBoost(stat: stat, delta: delta)]
        case let .sold(gold):
            // Surface as a plain ageAdvanced-style toast; gold change is in state.
            lastResults = [.itemDropped(itemId: "sold-for-\(gold)g", count: 1)]
        case .missing, .unknown:
            break
        }
        await save.write(next)
    }

    // MARK: - Tick

    /// Apply any new tokens in `events` to the pet. Idempotent across re-reads
    /// of the JSONL — only the *delta* of tokens since last seen is consumed.
    func tick(against events: [UsageEvent]) async {
        guard var current = state else { return }
        var newResults: [TickResult] = []
        for e in events {
            let key = eventKey(e)
            let already = accountedTokens[key, default: 0]
            let delta = e.grandTotal - already
            if delta <= 0 { continue }
            let (next, results) = TickProcessor.process(e, state: current, deltaTokens: delta)
            current = next
            accountedTokens[key] = e.grandTotal
            newResults.append(contentsOf: results)
        }
        if current != state {
            state = current
            lastResults = newResults
            await save.write(current)
        }
    }

    private func eventKey(_ e: UsageEvent) -> String {
        // messageId disambiguates when present; fall back to ISO timestamp.
        if let mid = e.messageId, !mid.isEmpty { return mid }
        return "ts:\(e.timestamp.timeIntervalSince1970):\(e.model)"
    }
}
