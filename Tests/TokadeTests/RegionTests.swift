@testable import Tokade
import XCTest

final class RegionTests: XCTestCase {
    func testIdentifierStripsHomePrefix() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let id = Region.identifier(for: "\(home)/code/tokade")
        XCTAssertEqual(id, "code/tokade")
    }

    func testIdentifierStripsTrailingSlash() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let id = Region.identifier(for: "\(home)/code/tokade/")
        XCTAssertEqual(id, "code/tokade")
    }

    func testHomeItselfMapsToHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(Region.identifier(for: home), "home")
    }

    func testOutsideHomeCollapsesToLastTwoSegments() {
        XCTAssertEqual(Region.identifier(for: "/opt/local/build/foo"), "build/foo")
        XCTAssertEqual(Region.identifier(for: "/tmp/scratch"), "tmp/scratch")
    }

    func testFlavorDetection() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokade-region-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        XCTAssertEqual(Region.flavor(for: tmp.path), .wilderness)

        try? "x".write(to: tmp.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Region.flavor(for: tmp.path), .ironFortress)

        try? "x".write(to: tmp.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        // Swift takes precedence in our order.
        XCTAssertEqual(Region.flavor(for: tmp.path), .stonework)
    }

    func testTickProcessorTracksRegionAndReputation() {
        let appearance = TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
        var state = TokegotchiState.newStarter(name: "Boba", appearance: appearance)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cwd = "\(home)/code/tokade"

        // Fire 50 events in the same cwd → +1 reputation.
        for i in 0..<50 {
            let e = UsageEvent(
                timestamp: Date(),
                model: "claude-sonnet-4-6",
                inputTokens: 0,
                cacheCreationTokens: 0,
                cacheReadTokens: 0,
                outputTokens: 1,
                sessionId: "s", messageId: "m\(i)",
                cwd: cwd, tools: [], slashCommand: nil
            )
            let (next, _) = TickProcessor.process(e, state: state, deltaTokens: 1)
            state = next
        }
        XCTAssertEqual(state.world.currentRegion, "code/tokade")
        XCTAssertEqual(state.world.reputation["code/tokade"], 1)
        // Flavor was seeded on first visit.
        XCTAssertNotNil(state.world.flavors?["code/tokade"])
    }
}
