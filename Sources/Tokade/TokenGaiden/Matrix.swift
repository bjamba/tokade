import Foundation

/// A baked sprite: a grid of palette-role glyphs.
///
/// Authored as SVG in `design/tokegotchi/`, rasterized at 32×54, then baked to
/// a text matrix where each cell is one of the role glyphs below. The runtime
/// substitutes per-Tokegotchi RGB at render time via `Palette` — see ADR 0005.
struct SpriteMatrix: Equatable {
    let width: Int
    let height: Int
    /// Row-major. `rows[y][x]` is one of the role glyphs in `PaletteRole`.
    let rows: [[Character]]

    static let canonicalWidth = 32
    static let canonicalHeight = 54
}

enum SpriteMatrixError: Error {
    case empty
    case raggedRows
}

extension SpriteMatrix {
    /// Parse a matrix file's text contents. Comment lines starting with `#` and
    /// blank lines are ignored. All remaining lines must have equal length.
    static func parse(_ text: String) throws -> SpriteMatrix {
        let lines: [Substring] = text.split(separator: "\n", omittingEmptySubsequences: false)
        let dataLines = lines.compactMap { line -> Substring? in
            if line.first == "#" { return nil }
            if line.isEmpty { return nil }
            return line
        }
        guard let first = dataLines.first else { throw SpriteMatrixError.empty }
        let w = first.count
        var rows: [[Character]] = []
        rows.reserveCapacity(dataLines.count)
        for line in dataLines {
            if line.count != w { throw SpriteMatrixError.raggedRows }
            rows.append(Array(line))
        }
        return SpriteMatrix(width: w, height: rows.count, rows: rows)
    }
}
