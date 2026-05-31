@testable import Tokade
import XCTest

/// Save-layer guards for Token Gaiden (issues #30, #34).
final class TokegotchiSavePersistenceTests: XCTestCase {
    private func makeTempGamesDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokade-tokegotchi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func appearance() -> TokegotchiState.Appearance {
        TokegotchiState.Appearance(
            skinSwatch: "lavender", irisSwatch: "blue",
            hairStyle: "horns", hairSwatch: "ivory"
        )
    }

    // MARK: - #30 — quest telemetry survives a save/load cycle (restart)

    func testQuestTelemetryRoundTripsThroughSave() async throws {
        let dir = try makeTempGamesDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let save = TokegotchiSave(directory: dir)

        var state = TokegotchiState.newStarter(name: "Pip", appearance: appearance())
        state.questTelemetryOrEmpty.toolCounts["Bash"] = 49
        state.questTelemetryOrEmpty.monstersDefeated = 3
        state.questTelemetryOrEmpty.cumulativeGold = 120
        await save.write(state)

        // Simulate a fresh launch: a new save actor reads from the same dir.
        let reloaded = await TokegotchiSave(directory: dir).read()
        XCTAssertNotNil(reloaded)
        XCTAssertEqual(reloaded?.questTelemetry?.toolCounts["Bash"], 49,
                       "quest progress must not reset on restart")
        XCTAssertEqual(reloaded?.questTelemetry?.monstersDefeated, 3)
        XCTAssertEqual(reloaded?.questTelemetry?.cumulativeGold, 120)
    }

    func testLegacySaveWithoutTelemetryDecodesAsEmpty() async throws {
        let dir = try makeTempGamesDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Write a state, then strip the questTelemetry key to mimic a pre-#30 save.
        var state = TokegotchiState.newStarter(name: "Old", appearance: appearance())
        state.questTelemetry = nil
        await TokegotchiSave(directory: dir).write(state)

        let reloaded = await TokegotchiSave(directory: dir).read()
        XCTAssertNotNil(reloaded)
        XCTAssertEqual(reloaded?.questTelemetryOrEmpty.monstersDefeated, 0)
        XCTAssertTrue(reloaded?.questTelemetryOrEmpty.toolCounts.isEmpty ?? false)
    }

    // MARK: - #34 — 0600 is preserved across an overwrite (replaceItemAt)

    func testSaveFileStays0600AcrossOverwrite() async throws {
        let dir = try makeTempGamesDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let save = TokegotchiSave(directory: dir)
        let fileURL = dir.appendingPathComponent(TokegotchiSave.filename)

        let state = TokegotchiState.newStarter(name: "Pip", appearance: appearance())
        await save.write(state) // first write — moveItem branch
        try assertMode0600(fileURL)

        var updated = state
        updated.progress.gold += 10
        await save.write(updated) // overwrite — replaceItemAt branch
        try assertMode0600(fileURL)
    }

    private func assertMode0600(_ url: URL, line: UInt = #line) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(perms, 0o600, "expected 0600, got \(String(perms, radix: 8))", line: line)
    }
}
