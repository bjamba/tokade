// bake.swift — convert a small PNG into a text matrix of palette indices.
// Palette is read from env vars so it stays in sync with render.sh.
// Usage: swift bake.swift <in.png> <out.matrix>

import AppKit
import CoreGraphics
import ImageIO

func hex(_ s: String) -> (UInt8, UInt8, UInt8) {
    var t = s
    if t.hasPrefix("#") { t.removeFirst() }
    let v = UInt32(t, radix: 16) ?? 0
    return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
}

let env = ProcessInfo.processInfo.environment

// Role-based palette. Index in matrix refers to ROLE — the runtime substitutes the user's chosen color.
let skin        = hex(env["SKIN"]        ?? "#C7A5D9")
let skinLight   = hex(env["SKIN_LIGHT"]  ?? "#DBC1E8")
let skinDark    = hex(env["SKIN_DARK"]   ?? "#A07AB8")
let hair        = hex(env["HAIR"]        ?? "#E8DCC4")
let hairDark    = hex(env["HAIR_DARK"]   ?? "#A89473")
let iris        = hex(env["IRIS"]        ?? "#4A7BC5")
let shirt       = hex(env["SHIRT"]       ?? "#5A7F3F")
let shirtLight  = hex(env["SHIRT_LIGHT"] ?? "#7DA055")
let shirtDark   = hex(env["SHIRT_DARK"]  ?? "#3F5A2A")
let pants       = hex(env["PANTS"]       ?? "#5C4033")
let pantsLight  = hex(env["PANTS_LIGHT"] ?? "#7C5C45")
let pantsDark   = hex(env["PANTS_DARK"]  ?? "#3D2920")
let belt        = hex(env["BELT"]        ?? "#8B6F47")
let dark        = hex(env["DARK"]        ?? "#1A1A2E")
let white       = hex(env["WHITE"]       ?? "#FFFFFF")

let palette: [(role: String, r: UInt8, g: UInt8, b: UInt8, glyph: Character)] = [
    ("transparent",  0, 0, 0, "."),
    ("outline",      dark.0, dark.1, dark.2, "1"),
    ("skin",         skin.0, skin.1, skin.2, "2"),
    ("skin-light",   skinLight.0, skinLight.1, skinLight.2, "3"),
    ("skin-dark",    skinDark.0, skinDark.1, skinDark.2, "4"),
    ("hair",         hair.0, hair.1, hair.2, "5"),
    ("hair-dark",    hairDark.0, hairDark.1, hairDark.2, "6"),
    ("iris",         iris.0, iris.1, iris.2, "7"),
    ("white",        white.0, white.1, white.2, "8"),
    ("shirt",        shirt.0, shirt.1, shirt.2, "9"),
    ("shirt-light",  shirtLight.0, shirtLight.1, shirtLight.2, "A"),
    ("shirt-dark",   shirtDark.0, shirtDark.1, shirtDark.2, "B"),
    ("pants",        pants.0, pants.1, pants.2, "C"),
    ("pants-light",  pantsLight.0, pantsLight.1, pantsLight.2, "D"),
    ("pants-dark",   pantsDark.0, pantsDark.1, pantsDark.2, "E"),
    ("belt",         belt.0, belt.1, belt.2, "F"),
]

// Alpha threshold: pixels with alpha below this are treated as transparent.
let alphaThreshold: UInt8 = 128

func nearestIndex(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Int {
    var best = 1, bestDist = Int.max
    for i in 1..<palette.count {
        let p = palette[i]
        let dr = Int(r) - Int(p.r)
        let dg = Int(g) - Int(p.g)
        let db = Int(b) - Int(p.b)
        let d = dr*dr + dg*dg + db*db
        if d < bestDist { bestDist = d; best = i }
    }
    return best
}

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: bake <in.png> <out.matrix>"); exit(1) }

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let cg  = CGImageSourceCreateImageAtIndex(src, 0, nil) else { exit(2) }
let w = cg.width, h = cg.height
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let bm = CGImageAlphaInfo.premultipliedLast.rawValue
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: bm)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
let buf = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)

// Pass 1: build an opacity mask via threshold. opaque[y*w+x] = true if alpha >= threshold.
var opaque = [Bool](repeating: false, count: w * h)
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        if buf[i + 3] >= alphaThreshold { opaque[y * w + x] = true }
    }
}

// Pass 2: detect outline cells — transparent cells adjacent (4-neighbors) to opaque cells.
var isOutline = [Bool](repeating: false, count: w * h)
for y in 0..<h {
    for x in 0..<w {
        if opaque[y * w + x] { continue }
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
            let nx = x + dx, ny = y + dy
            if nx < 0 || nx >= w || ny < 0 || ny >= h { continue }
            if opaque[ny * w + nx] { isOutline[y * w + x] = true; break }
        }
    }
}

// Pass 3: write matrix.
var out = "# matrix \(w)x\(h)\n# palette (roles — runtime substitutes actual colors):\n"
for p in palette {
    out += String(format: "#  %@ = %@\n", String(p.glyph), p.role)
}
out += "#\n"
for y in 0..<h {
    var row = ""
    for x in 0..<w {
        let cellIdx = y * w + x
        let i = cellIdx * 4
        let glyph: Character
        if isOutline[cellIdx] {
            glyph = "1"  // outline role
        } else if !opaque[cellIdx] {
            glyph = "."  // transparent
        } else {
            // Unpremultiply, then match to nearest palette role.
            let a = buf[i + 3]
            let af = Double(a) / 255.0
            let ur = UInt8(min(255, max(0, Int(Double(buf[i])     / af))))
            let ug = UInt8(min(255, max(0, Int(Double(buf[i + 1]) / af))))
            let ub = UInt8(min(255, max(0, Int(Double(buf[i + 2]) / af))))
            glyph = palette[nearestIndex(ur, ug, ub)].glyph
        }
        row.append(glyph)
    }
    out += row + "\n"
}
try out.write(toFile: args[2], atomically: true, encoding: .utf8)
print("baked → \(args[2])  (\(w)x\(h))")
