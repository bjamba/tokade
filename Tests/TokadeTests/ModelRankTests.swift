import XCTest
@testable import Tokade

/// Tier + version parsing drives the entire model color/sort palette.
/// If `modelRank` mis-classifies a model name, the wrong tier color renders
/// and the legend sort order is wrong. Lock the canonical model names down.
final class ModelRankTests: XCTestCase {

    func testHaikuClassification() {
        let r = modelRank("claude-haiku-4-5")
        XCTAssertEqual(r.tier, .haiku)
        XCTAssertEqual(r.major, 4)
        XCTAssertEqual(r.minor, 5)
    }

    func testSonnetClassification() {
        let r = modelRank("claude-sonnet-4-6")
        XCTAssertEqual(r.tier, .sonnet)
        XCTAssertEqual(r.major, 4)
        XCTAssertEqual(r.minor, 6)
    }

    func testOpusClassification() {
        let r = modelRank("claude-opus-4-7")
        XCTAssertEqual(r.tier, .opus)
        XCTAssertEqual(r.major, 4)
        XCTAssertEqual(r.minor, 7)
    }

    func testDateSuffixedHaikuStillClassified() {
        // Some Claude Code messages include a trailing date stamp.
        let r = modelRank("claude-haiku-4-5-20251001")
        XCTAssertEqual(r.tier, .haiku)
        XCTAssertEqual(r.major, 4)
        XCTAssertEqual(r.minor, 5)
    }

    func testUnknownFallsToOther() {
        let r = modelRank("some-future-model-42")
        XCTAssertEqual(r.tier, .other)
    }

    func testSortedModelsOrderingHaikuSonnetOpus() {
        let unsorted = ["claude-opus-4-7", "claude-haiku-4-5", "claude-sonnet-4-6"]
        let sorted = sortedModels(unsorted)
        XCTAssertEqual(sorted, [
            "claude-haiku-4-5",
            "claude-sonnet-4-6",
            "claude-opus-4-7"
        ])
    }

    func testSortedModelsWithinTierAscendingVersion() {
        let unsorted = ["claude-opus-4-7", "claude-opus-4-5", "claude-opus-4-6"]
        let sorted = sortedModels(unsorted)
        XCTAssertEqual(sorted, [
            "claude-opus-4-5",
            "claude-opus-4-6",
            "claude-opus-4-7"
        ])
    }
}
