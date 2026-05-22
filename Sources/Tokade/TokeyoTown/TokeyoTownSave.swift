import Foundation
import os.log

/// Read/write Tokeyo Town saves at `~/.tokade/games/tokeyotown/`.
///
/// Layout:
///   ~/.tokade/games/tokeyotown/
///     index.json                      ← active town + town list
///     <townId>.json                   ← per-town save
///     archive/<townId>-<isoDate>.json ← old saves moved here on replace
///
/// Writes are atomic (tmp + replace) with mode 0o600 to match the rest of
/// Tokade's privacy promise. The 0o600 here is enforced by scripts/check.sh.
actor TokeyoTownSave {
    private let log = Logger(subsystem: "com.bjamba.tokade", category: "TokeyoTownSave")

    private var baseDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".tokade/games/tokeyotown")
    }

    private var indexURL: URL { baseDir.appendingPathComponent("index.json") }
    private var archiveDir: URL { baseDir.appendingPathComponent("archive") }
    private func townURL(_ id: String) -> URL {
        baseDir.appendingPathComponent("\(id).json")
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    func readIndex() async -> TokeyoTownIndex {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return .empty }
        do {
            let data = try Data(contentsOf: indexURL)
            return try decoder().decode(TokeyoTownIndex.self, from: data)
        } catch {
            log.warning("Failed to read index: \(String(describing: error), privacy: .public)")
            return .empty
        }
    }

    func readActiveTown() async -> TokeyoTownState? {
        let index = await readIndex()
        guard let id = index.activeTownId else { return nil }
        return await readTown(id: id)
    }

    func readTown(id: String) async -> TokeyoTownState? {
        let url = townURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder().decode(TokeyoTownState.self, from: data)
        } catch {
            log.warning("Failed to read town \(id, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Atomic write of a town save with 0o600 perms. Best-effort — logs warnings.
    func writeTown(_ state: TokeyoTownState) async {
        let url = townURL(state.townId)
        do {
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
            let data = try encoder().encode(state)
            let tmp = url.appendingPathExtension("tmp")
            try data.write(to: tmp, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tmp.path
            )
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }
        } catch {
            log.warning("Failed to write town: \(String(describing: error), privacy: .public)")
        }
    }

    /// Atomic write of the index with 0o600 perms.
    func writeIndex(_ index: TokeyoTownIndex) async {
        do {
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
            let data = try encoder().encode(index)
            let tmp = indexURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tmp.path
            )
            if FileManager.default.fileExists(atPath: indexURL.path) {
                _ = try? FileManager.default.replaceItemAt(indexURL, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: indexURL)
            }
        } catch {
            log.warning("Failed to write index: \(String(describing: error), privacy: .public)")
        }
    }

    /// Move a town's save into `archive/` instead of deleting it.
    /// Called when the user starts a new town and the one-town-at-a-time
    /// MVP rule says we have to set aside the current one.
    func archiveTown(id: String) async {
        let url = townURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let dest = archiveDir.appendingPathComponent("\(id)-\(stamp).json")
        do {
            try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: dest)
        } catch {
            log.warning("Failed to archive town: \(String(describing: error), privacy: .public)")
        }
    }

    /// Wipe everything. Used by "Erase history…" to give a clean slate.
    func eraseAll() async {
        try? FileManager.default.removeItem(at: baseDir)
    }
}
