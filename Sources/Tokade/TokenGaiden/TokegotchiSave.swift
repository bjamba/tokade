import Foundation
import os.log

/// Read/write the Tokegotchi save file at `~/.tokade/games/tokegotchi.json`.
/// Writes are atomic (tmp + mv) and the file is mode 0600 to match the rest
/// of Tokade's privacy promise.
actor TokegotchiSave {
    private let log = Logger(subsystem: "com.bjamba.tokade", category: "TokegotchiSave")

    static let filename = "tokegotchi.json"

    private var fileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".tokade/games/\(Self.filename)")
    }

    /// Read the save, or nil if missing / unreadable. Logs but does not throw
    /// on parse errors — the caller treats nil as "show character creator".
    func read() async -> TokegotchiState? {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(TokegotchiState.self, from: data)
        } catch {
            log.warning("Failed to read save: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Atomic write with 0600 perms. Best-effort — logs warnings on failure.
    func write(_ state: TokegotchiState) async {
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
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
            log.warning("Failed to write save: \(String(describing: error), privacy: .public)")
        }
    }

    /// Delete the save file. Used by "Erase history…" so a clean slate
    /// includes Token Gaiden.
    func erase() async {
        let url = fileURL
        try? FileManager.default.removeItem(at: url)
    }
}
