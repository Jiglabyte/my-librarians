#!/usr/bin/env swift
// Run from the ScreenLapse/ project directory:
//   swift create_icon.swift
// Generates PNG icon files into ScreenLapse/Assets.xcassets/AppIcon.appiconset/

import Foundation
import CoreGraphics
import ImageIO

func drawIcon(pixelSize size: Int) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Cannot create CGContext at size \(size)") }

    let f = CGFloat(size)
    let cx = f * 0.5
    let cy = f * 0.5

    // ── Background: deep navy-black gradient ────────────────────────────
    let bgComponents: [CGFloat] = [
        0.09, 0.09, 0.16, 1.0,   // top: indigo-black
        0.05, 0.04, 0.10, 1.0    // bottom: darker
    ]
    let bgGrad = CGGradient(
        colorSpace: cs, colorComponents: bgComponents, locations: [0, 1], count: 2
    )!
    ctx.drawLinearGradient(bgGrad,
                           start: CGPoint(x: cx, y: f),
                           end: CGPoint(x: cx, y: 0),
                           options: [])

    // ── Outer white ring ─────────────────────────────────────────────────
    let ringR = f * 0.345
    let ringW = max(1.5, f * 0.055)
    let ringColor: [CGFloat] = [1.0, 1.0, 1.0, 0.92]
    ctx.setStrokeColor(CGColor(colorSpace: cs, components: ringColor)!)
    ctx.setLineWidth(ringW)
    ctx.strokeEllipse(in: CGRect(x: cx - ringR, y: cy - ringR,
                                  width: ringR * 2, height: ringR * 2))

    // ── Inner red record dot ─────────────────────────────────────────────
    let dotR = f * 0.210
    let dotRect = CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)

    // Radial gradient: bright red center → deep red edge
    let redComponents: [CGFloat] = [
        1.00, 0.26, 0.16, 1.0,
        0.82, 0.06, 0.03, 1.0
    ]
    let redGrad = CGGradient(
        colorSpace: cs, colorComponents: redComponents, locations: [0, 1], count: 2
    )!

    ctx.saveGState()
    ctx.addEllipse(in: dotRect)
    ctx.clip()
    ctx.drawRadialGradient(
        redGrad,
        startCenter: CGPoint(x: cx - dotR * 0.18, y: cy + dotR * 0.22),
        startRadius: 0,
        endCenter: CGPoint(x: cx, y: cy),
        endRadius: dotR * 1.05,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Specular shine (top arc, translucent white)
    let shineComponents: [CGFloat] = [1, 1, 1, 0.28,   1, 1, 1, 0.0]
    let shineGrad = CGGradient(
        colorSpace: cs, colorComponents: shineComponents, locations: [0, 1], count: 2
    )!
    ctx.drawLinearGradient(shineGrad,
                           start: CGPoint(x: cx, y: cy + dotR),
                           end: CGPoint(x: cx, y: cy + dotR * 0.05),
                           options: [])
    ctx.restoreGState()

    return ctx.makeImage()!
}

func savePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
        fputs("ERROR: cannot create PNG destination at \(path)\n", stderr); return
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        fputs("ERROR: failed to write \(path)\n", stderr); return
    }
    print("  ✓ \(URL(fileURLWithPath: path).lastPathComponent)")
}

// ── Main ─────────────────────────────────────────────────────────────────────

let fm = FileManager.default
let cwd = fm.currentDirectoryPath
let assetDir = "\(cwd)/ScreenLapse/Assets.xcassets/AppIcon.appiconset"
try! fm.createDirectory(atPath: assetDir, withIntermediateDirectories: true)

print("Generating ScreenLapse app icon…")

// (filename, pixel size)
let icons: [(String, Int)] = [
    ("icon_16x16@1x.png",     16),
    ("icon_16x16@2x.png",     32),
    ("icon_32x32@1x.png",     32),
    ("icon_32x32@2x.png",     64),
    ("icon_128x128@1x.png",  128),
    ("icon_128x128@2x.png",  256),
    ("icon_256x256@1x.png",  256),
    ("icon_256x256@2x.png",  512),
    ("icon_512x512@1x.png",  512),
    ("icon_512x512@2x.png", 1024),
]

// Cache renders by pixel size (avoids re-drawing identical sizes)
var cache: [Int: CGImage] = [:]
for (name, px) in icons {
    if cache[px] == nil { cache[px] = drawIcon(pixelSize: px) }
    savePNG(cache[px]!, to: "\(assetDir)/\(name)")
}

print("\nDone. Rebuild with:  ./build.sh run")
