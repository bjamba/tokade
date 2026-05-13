// render_matrix.swift — render a baked matrix file to PNG using a palette from env vars.
// Demonstrates that matrix-as-runtime + palette-swap = N color combos from 1 matrix.
//
// Usage: swift render_matrix.swift <in.matrix> <out.png> [upscale]

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func hex(_ s: String) -> (UInt8, UInt8, UInt8) {
    var t = s
    if t.hasPrefix("#") { t.removeFirst() }
    let v = UInt32(t, radix: 16) ?? 0
    return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
}

let env = ProcessInfo.processInfo.environment
let skin       = hex(env["SKIN"]        ?? "#C7A5D9")
let skinLight  = hex(env["SKIN_LIGHT"]  ?? "#DBC1E8")
let skinDark   = hex(env["SKIN_DARK"]   ?? "#A07AB8")
let hair       = hex(env["HAIR"]        ?? "#E8DCC4")
let hairDark   = hex(env["HAIR_DARK"]   ?? "#A89473")
let iris       = hex(env["IRIS"]        ?? "#4A7BC5")
let shirt      = hex(env["SHIRT"]       ?? "#5A7F3F")
let shirtLight = hex(env["SHIRT_LIGHT"] ?? "#7DA055")
let shirtDark  = hex(env["SHIRT_DARK"]  ?? "#3F5A2A")
let pants      = hex(env["PANTS"]       ?? "#5C4033")
let pantsLight = hex(env["PANTS_LIGHT"] ?? "#7C5C45")
let pantsDark  = hex(env["PANTS_DARK"]  ?? "#3D2920")
let belt       = hex(env["BELT"]        ?? "#8B6F47")
let dark       = hex(env["DARK"]        ?? "#1A1A2E")
let white      = hex(env["WHITE"]       ?? "#FFFFFF")

// glyph → (r, g, b, a)
let lut: [Character: (UInt8, UInt8, UInt8, UInt8)] = [
    ".": (0, 0, 0, 0),
    "1": (dark.0, dark.1, dark.2, 255),
    "2": (skin.0, skin.1, skin.2, 255),
    "3": (skinLight.0, skinLight.1, skinLight.2, 255),
    "4": (skinDark.0, skinDark.1, skinDark.2, 255),
    "5": (hair.0, hair.1, hair.2, 255),
    "6": (hairDark.0, hairDark.1, hairDark.2, 255),
    "7": (iris.0, iris.1, iris.2, 255),
    "8": (white.0, white.1, white.2, 255),
    "9": (shirt.0, shirt.1, shirt.2, 255),
    "A": (shirtLight.0, shirtLight.1, shirtLight.2, 255),
    "B": (shirtDark.0, shirtDark.1, shirtDark.2, 255),
    "C": (pants.0, pants.1, pants.2, 255),
    "D": (pantsLight.0, pantsLight.1, pantsLight.2, 255),
    "E": (pantsDark.0, pantsDark.1, pantsDark.2, 255),
    "F": (belt.0, belt.1, belt.2, 255),
]

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: render_matrix <in.matrix> <out.png> [upscale]"); exit(1) }
let scale = args.count > 3 ? Int(args[3]) ?? 1 : 1

let raw = try String(contentsOfFile: args[1], encoding: .utf8)
let rows: [String] = raw.split(whereSeparator: { $0 == "\n" })
    .map(String.init)
    .filter { !$0.hasPrefix("#") && !$0.isEmpty }

let h = rows.count
let w = rows[0].count

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let bm = CGImageAlphaInfo.premultipliedLast.rawValue
let ctx = CGContext(data: nil, width: w * scale, height: h * scale,
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: bm)!
let buf = ctx.data!.bindMemory(to: UInt8.self, capacity: w * scale * h * scale * 4)

for (y, row) in rows.enumerated() {
    for (x, glyph) in row.enumerated() {
        let (r, g, b, a) = lut[glyph] ?? (0, 0, 0, 0)
        // Paint the scale×scale block for this matrix cell.
        // CGContext y is bottom-up — flip.
        for sy in 0..<scale {
            for sx in 0..<scale {
                let px = x * scale + sx
                let py = (h - 1 - y) * scale + sy
                let i = (py * w * scale + px) * 4
                buf[i]     = UInt8((Int(r) * Int(a)) / 255)
                buf[i + 1] = UInt8((Int(g) * Int(a)) / 255)
                buf[i + 2] = UInt8((Int(b) * Int(a)) / 255)
                buf[i + 3] = a
            }
        }
    }
}

guard let img = ctx.makeImage() else { exit(2) }
let url = URL(fileURLWithPath: args[2]) as CFURL
guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else { exit(3) }
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("rendered \(args[2])  \(w)x\(h) cells × \(scale)x")
