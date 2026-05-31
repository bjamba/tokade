@testable import Tokade
import XCTest

/// Issue #43 (model-mix half): the model you run *on this repo* shapes WHICH
/// resources you earn. Opus → thinking (knowledge + industry), Haiku →
/// building (lumber + coin), Sonnet → neutral baseline, out-of-repo → nothing.
/// These tests pin the additive bonus and that it leaves the base v3.x
/// economy (and retired-resource zeroing) untouched.
final class ModelMixResourcesTests: XCTestCase {
    private func event(
        ts: Date = Date(),
        model: String,
        tokens: Int,
        cwd: String?,
        messageId: String
    ) -> UsageEvent {
        UsageEvent(
            timestamp: ts,
            model: model,
            inputTokens: tokens / 4,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            outputTokens: tokens - tokens / 4,
            sessionId: nil,
            messageId: messageId,
            cwd: cwd,
            tools: [],
            slashCommand: nil
        )
    }

    /// Enough tokens to clear the bonus threshold a couple of times over.
    private var heavyTokens: Int { ResourceAccrual.modelBonusTokensPerPoint * 2 }

    // MARK: - modelResourceBonus (pure helper)

    func testOpusHeavyAddsThinkingNotBuilding() {
        let events = [event(model: "claude-opus-4-7", tokens: heavyTokens, cwd: "/repo", messageId: "o1")]
        let bonus = ResourceAccrual.modelResourceBonus(events: events, repoPath: "/repo")
        XCTAssertEqual(bonus.knowledge, 2)
        XCTAssertEqual(bonus.industry, 2)
        XCTAssertEqual(bonus.lumber, 0)
        XCTAssertEqual(bonus.coin, 0)
    }

    func testHaikuHeavyAddsBuildingNotThinking() {
        let events = [event(model: "claude-haiku-4-5", tokens: heavyTokens, cwd: "/repo", messageId: "h1")]
        let bonus = ResourceAccrual.modelResourceBonus(events: events, repoPath: "/repo")
        XCTAssertEqual(bonus.lumber, 2)
        XCTAssertEqual(bonus.coin, 2)
        XCTAssertEqual(bonus.knowledge, 0)
        XCTAssertEqual(bonus.industry, 0)
    }

    func testSonnetIsNeutral() {
        let events = [event(model: "claude-sonnet-4-5", tokens: heavyTokens, cwd: "/repo", messageId: "s1")]
        let bonus = ResourceAccrual.modelResourceBonus(events: events, repoPath: "/repo")
        XCTAssertEqual(bonus, .zero)
    }

    func testUnknownModelIsNeutral() {
        let events = [event(model: "some-future-model", tokens: heavyTokens, cwd: "/repo", messageId: "u1")]
        let bonus = ResourceAccrual.modelResourceBonus(events: events, repoPath: "/repo")
        XCTAssertEqual(bonus, .zero)
    }

    func testOutOfRepoEventsAddNothing() {
        let events = [event(model: "claude-opus-4-7", tokens: heavyTokens, cwd: "/some/other/repo", messageId: "x1")]
        let bonus = ResourceAccrual.modelResourceBonus(events: events, repoPath: "/repo")
        XCTAssertEqual(bonus, .zero)
    }

    func testBonusAccumulatesAcrossManySmallTurnsOfSameFamily() {
        // Many sub-threshold Opus turns still sum to bonus points.
        let now = Date()
        let per = ResourceAccrual.modelBonusTokensPerPoint / 3 // 3 turns ≈ 1 point
        let events = (0..<3).map {
            event(ts: now.addingTimeInterval(Double($0)), model: "claude-opus-4-7", tokens: per, cwd: "/repo", messageId: "o\($0)")
        }
        let bonus = ResourceAccrual.modelResourceBonus(events: events, repoPath: "/repo")
        XCTAssertEqual(bonus.knowledge, 1)
        XCTAssertEqual(bonus.industry, 1)
    }

    func testModelFamilyClassification() {
        XCTAssertEqual(ResourceAccrual.modelFamily("claude-opus-4-7"), .opus)
        XCTAssertEqual(ResourceAccrual.modelFamily("claude-sonnet-4-5"), .sonnet)
        XCTAssertEqual(ResourceAccrual.modelFamily("claude-haiku-4-5"), .haiku)
        XCTAssertEqual(ResourceAccrual.modelFamily("<synthetic>"), .other)
    }

    // MARK: - accrue() folds the bonus in additively

    func testAccrueFoldsOpusBonusOnTopOfBaseEconomy() {
        let now = Date()
        let events = [event(model: "claude-opus-4-7", tokens: heavyTokens, cwd: "/repo", messageId: "a1")]
        let (delta, _) = ResourceAccrual.accrue(
            events: events,
            repoPath: "/repo",
            accounted: .init(),
            currentSessionCwd: nil
        )
        // Base coin: grandTotal / 1000. Opus adds no coin bonus.
        XCTAssertEqual(delta.coin, heavyTokens / 1000)
        // Opus thinking bonus, additive on top of zero base tools.
        XCTAssertEqual(delta.knowledge, 2)
        XCTAssertEqual(delta.industry, 2)
        XCTAssertEqual(delta.lumber, 0)
        // Retired resources stay zeroed.
        XCTAssertEqual(delta.stability, 0)
        XCTAssertEqual(delta.inspiration, 0)
    }

    func testAccrueFoldsHaikuBonusIntoCoinAndLumber() {
        let now = Date()
        let events = [event(model: "claude-haiku-4-5", tokens: heavyTokens, cwd: "/repo", messageId: "a2")]
        let (delta, _) = ResourceAccrual.accrue(
            events: events,
            repoPath: "/repo",
            accounted: .init(),
            currentSessionCwd: nil
        )
        // Base coin + Haiku building coin bonus (2 points).
        XCTAssertEqual(delta.coin, heavyTokens / 1000 + 2)
        XCTAssertEqual(delta.lumber, 2)
        XCTAssertEqual(delta.knowledge, 0)
        XCTAssertEqual(delta.industry, 0)
    }
}
