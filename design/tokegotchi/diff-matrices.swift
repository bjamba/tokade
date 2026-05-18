// diff-matrices.swift — produce a "just the cosmetic" matrix by subtracting
// a naked-base matrix from a fully-clothed matrix. Cells that match the base
// become transparent; cells that differ keep the full matrix's value.
//
// Usage: swift diff-matrices.swift <base.matrix> <full.matrix> <out.matrix>
//
// Used to extract per-animation-frame cosmetic overlays from full-Tokegotchi
// renders, so cosmetics animate together with their underlying body parts.

import Foundation

func readMatrix(_ path: String) throws -> (rows: [[Character]], header: String) {
    let raw = try String(contentsOfFile: path, encoding: .utf8)
    var header = ""
    var data: [[Character]] = []
    for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.hasPrefix("#") || line.isEmpty {
            header += line + "\n"
            continue
        }
        data.append(Array(line))
    }
    return (data, header)
}

let args = CommandLine.arguments
guard args.count == 4 else { print("usage: diff-matrices <base> <full> <out>"); exit(1) }
let baseM  = try readMatrix(args[1])
let fullM  = try readMatrix(args[2])
guard baseM.rows.count == fullM.rows.count, baseM.rows.first?.count == fullM.rows.first?.count else {
    print("dimension mismatch"); exit(2)
}

var out = baseM.header
for (y, row) in fullM.rows.enumerated() {
    var diff: [Character] = []
    for (x, g) in row.enumerated() {
        diff.append(g == baseM.rows[y][x] ? "." : g)
    }
    out += String(diff) + "\n"
}
try out.write(toFile: args[3], atomically: true, encoding: .utf8)
