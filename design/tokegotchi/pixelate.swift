// pixelate.swift — render pipeline for Tokegotchi sprites.
// Pipeline: in.png → (optional outline at source res) → nearest-neighbor upscale → (optional CRT scanlines) → out.png
//
// Usage: swift pixelate.swift <in.png> <out.png> <scale> [outline] [crt]
//
// Notes:
// - `outline` adds a 1-pixel dark border around the silhouette AT SOURCE RESOLUTION, so it scales as 1 chunky pixel.
//   For cosmetics, run outline ONLY on the final composite, not per-layer.
// - `crt` darkens every 3rd row of the upscaled image to simulate CRT scanlines.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4, let scale = Int(args[3]) else {
    FileHandle.standardError.write("usage: pixelate <in.png> <out.png> <scale> [outline] [crt]\n".data(using: .utf8)!)
    exit(1)
}
let doOutline = args.contains("outline")
let doCRT     = args.contains("crt")

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let cg  = CGImageSourceCreateImageAtIndex(src, 0, nil) else { exit(2) }

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let bm = CGImageAlphaInfo.premultipliedLast.rawValue
func makeCtx(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: bm)!
}

// Decode source into editable buffer at native resolution.
let w0 = cg.width, h0 = cg.height
let smallCtx = makeCtx(w0, h0)
smallCtx.draw(cg, in: CGRect(x: 0, y: 0, width: w0, height: h0))
guard let smallData = smallCtx.data else { exit(3) }
let buf = smallData.bindMemory(to: UInt8.self, capacity: w0 * h0 * 4)

// Outline pass: any transparent pixel adjacent to a non-transparent neighbor becomes outline color.
if doOutline {
    let (or, og, ob): (UInt8, UInt8, UInt8) = (0x1A, 0x1A, 0x2E)
    var marks = [Bool](repeating: false, count: w0 * h0)
    let neighbors = [(-1, 0), (1, 0), (0, -1), (0, 1)]
    for y in 0..<h0 {
        for x in 0..<w0 {
            let i = (y * w0 + x) * 4
            if buf[i + 3] != 0 { continue }
            for (dx, dy) in neighbors {
                let nx = x + dx, ny = y + dy
                if nx < 0 || nx >= w0 || ny < 0 || ny >= h0 { continue }
                let ni = (ny * w0 + nx) * 4
                if buf[ni + 3] != 0 { marks[y * w0 + x] = true; break }
            }
        }
    }
    for y in 0..<h0 {
        for x in 0..<w0 where marks[y * w0 + x] {
            let i = (y * w0 + x) * 4
            buf[i] = or; buf[i + 1] = og; buf[i + 2] = ob; buf[i + 3] = 0xFF
        }
    }
}

guard let smallCG = smallCtx.makeImage() else { exit(4) }

// Nearest-neighbor upscale.
let w1 = w0 * scale, h1 = h0 * scale
let bigCtx = makeCtx(w1, h1)
bigCtx.interpolationQuality = .none
bigCtx.draw(smallCG, in: CGRect(x: 0, y: 0, width: w1, height: h1))

// Stylization: every other SOURCE pixel row darkened ~12% for a subtle scanline at the pixel-grid level.
// Reads as a stylization choice rather than a fake-CRT simulation.
if doCRT {
    guard let bigData = bigCtx.data else { exit(5) }
    let big = bigData.bindMemory(to: UInt8.self, capacity: w1 * h1 * 4)
    let darken = 0.88
    for y in 0..<h1 {
        let sourceRow = y / scale
        if sourceRow % 2 != 0 { continue }
        for x in 0..<w1 {
            let i = (y * w1 + x) * 4
            if big[i + 3] == 0 { continue }
            big[i]     = UInt8(Double(big[i])     * darken)
            big[i + 1] = UInt8(Double(big[i + 1]) * darken)
            big[i + 2] = UInt8(Double(big[i + 2]) * darken)
        }
    }
}

guard let out = bigCtx.makeImage() else { exit(6) }
let url = URL(fileURLWithPath: args[2]) as CFURL
guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else { exit(7) }
CGImageDestinationAddImage(dest, out, nil)
CGImageDestinationFinalize(dest)
