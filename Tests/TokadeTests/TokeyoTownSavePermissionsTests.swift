@testable import Tokade
import XCTest

/// Behavioral 0600 guard for Tokeyo Town saves (issue #35). Town saves contain
/// repo paths the user adopted; CLAUDE.md promises owner-only perms. Covers the
/// `replaceItemAt` overwrite path, which does not inherit the tmp file's mode.
final class TokeyoTownSavePermissionsTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokade-tokeyotown-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func repo() -> TokeyoTownState.RepoSnapshot {
        TokeyoTownState.RepoSnapshot(
            path: "/p", displayName: "p", scannedAt: .now,
            primaryLanguage: "swift", biome: .beach, era: .modern,
            ageInDays: 10, loc: 1234, mapSize: 16,
            contributorCount: 1, lushness: 0.5
        )
    }

    private func assertMode0600(_ url: URL, line: UInt = #line) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(perms, 0o600, "expected 0600, got \(String(perms, radix: 8))", line: line)
    }

    func testTownSaveIs0600AcrossOverwrite() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let save = TokeyoTownSave(directory: dir)

        var state = TokeyoTownState.fresh(townId: "abcd1234abcd1234", repo: repo())
        await save.writeTown(state)
        let url = dir.appendingPathComponent("abcd1234abcd1234.json")
        try assertMode0600(url)

        state.resources.coin += 5
        await save.writeTown(state) // replaceItemAt branch
        try assertMode0600(url)
    }

    func testIndexIs0600AcrossOverwrite() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let save = TokeyoTownSave(directory: dir)

        await save.writeIndex(.empty)
        let url = dir.appendingPathComponent("index.json")
        try assertMode0600(url)

        await save.writeIndex(.empty) // replaceItemAt branch
        try assertMode0600(url)
    }
}
