@testable import Tokade
import XCTest

final class TokegotchiStateTests: XCTestCase {
    func testHpMaxAndSpMaxAreDerivedFromStats() {
        var vitals = TokegotchiState.Vitals(
            hp: 0, sp: 0,
            stats: TokegotchiState.Stats(str: 10, dex: 20, int: 5, agi: 5, cha: 10)
        )
        XCTAssertEqual(vitals.hpMax, 80 + (10 + 20) * 2)   // 140
        XCTAssertEqual(vitals.spMax, 40 + (5 + 10) * 2)    // 70
        vitals.hp = 200; vitals.clamp()
        XCTAssertEqual(vitals.hp, vitals.hpMax)
        vitals.hp = -10; vitals.clamp()
        XCTAssertEqual(vitals.hp, 0)
    }

    func testNewStarterHasFullHpSp() {
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        let s = TokegotchiState.newStarter(name: "Boba", appearance: appearance)
        XCTAssertEqual(s.identity.generation, 1)
        XCTAssertEqual(s.identity.ageTokens, 0)
        XCTAssertEqual(s.vitals.hp, s.vitals.hpMax)
        XCTAssertEqual(s.vitals.sp, s.vitals.spMax)
        XCTAssertEqual(s.vitals.stats, .starter)
        XCTAssertEqual(s.inventory.equippedCosmetic["hair"], "horns")
    }

    func testIsAgedOutAndIsCritical() {
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        var s = TokegotchiState.newStarter(name: "Boba", appearance: appearance)
        XCTAssertFalse(s.isAgedOut)
        XCTAssertFalse(s.isCritical)
        s.identity.ageTokens = s.identity.lifespanTokens + 1
        XCTAssertTrue(s.isAgedOut)
        s.vitals.hp = 0
        XCTAssertTrue(s.isCritical)
    }

    func testCodableRoundTrip() throws {
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "peach", irisSwatch: "green",
            hairStyle: "flame", hairSwatch: "magenta"
        )
        // Use a date with zero subsecond precision so the iso8601 round-trip
        // doesn't lose fractional seconds. (The save format intentionally drops
        // them — see TokegotchiSave.)
        let stableDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-13T18:00:00Z"))
        var s = TokegotchiState.newStarter(
            name: "Snickerdoodle", appearance: appearance, bornAt: stableDate
        )
        s.identity.bornAt = stableDate
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(s)
        let round = try decoder.decode(TokegotchiState.self, from: data)
        XCTAssertEqual(round, s)
    }
}
