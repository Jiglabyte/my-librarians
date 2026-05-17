#!/usr/bin/swift
// Run: swift create_icon.swift
// Generates ScreenLapse AppIcon PNGs into Assets.xcassets/AppIcon.appiconset/
import Cocoa
import CoreGraphics

func makeIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    defer { img.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return img }
    ctx.saveGState()
    defer { ctx.restoreGState() }

    // Clip to circle
    let circlePath = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: s, height: s), transform: nil)
    ctx.addPath(circlePath)
    ctx.clip()

    // Navy radial gradient background
    let colors = [
        NSColor(red: 0.10, green: 0.165, blue: 0.29, alpha: 1).cgColor,
        NSColor(red: 0.04, green: 0.086, blue: 0.157, alpha: 1).cgColor,
    ] as CFArray
    let locs: [CGFloat] = [0, 1]
    let space = CGColorSpaceCreateDeviceRGB()
    if let grad = CGGradient(colorsSpace: space, colors: colors, locations: locs) {
        ctx.drawRadialGradient(grad,
            startCenter: CGPoint(x: s * 0.42, y: s * 0.58), startRadius: 0,
            endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: s * 0.52,
            options: [.drawsAfterEndLocation])
    }

    // White outer ring
    let ringW = max(1.5, s * 0.045)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.78).cgColor)
    ctx.setLineWidth(ringW)
    ctx.strokeEllipse(in: CGRect(x: ringW, y: ringW, width: s - ringW * 2, height: s - ringW * 2))

    // Red record dot
    let dotR = s * 0.30
    let cx = s / 2, cy = s / 2
    let redColors = [
        NSColor(red: 1.0, green: 0.38, blue: 0.31, alpha: 1).cgColor,
        NSColor(red: 0.86, green: 0.118, blue: 0.118, alpha: 1).cgColor,
    ] as CFArray
    let dotLocs: [CGFloat] = [0, 1]
    if let dotGrad = CGGradient(colorsSpace: space, colors: redColors, locations: dotLocs) {
        ctx.drawRadialGradient(dotGrad,
            startCenter: CGPoint(x: cx - dotR * 0.15, y: cy + dotR * 0.15), startRadius: 0,
            endCenter: CGPoint(x: cx, y: cy), endRadius: dotR,
            options: [.drawsAfterEndLocation])
    }

    // Specular highlight on dot
    let hlR = dotR * 0.28
    let hlX = cx - dotR * 0.22
    let hlY = cy + dotR * 0.22
    let hlColors = [
        NSColor(white: 1.0, alpha: 0.70).cgColor,
        NSColor(white: 1.0, alpha: 0.0).cgColor,
    ] as CFArray
    let hlLocs: [CGFloat] = [0, 1]
    if let hlGrad = CGGradient(colorsSpace: space, colors: hlColors, locations: hlLocs) {
        ctx.drawRadialGradient(hlGrad,
            startCenter: CGPoint(x: hlX, y: hlY), startRadius: 0,
            endCenter: CGPoint(x: hlX, y: hlY), endRadius: hlR,
            options: [.drawsAfterEndLocation])
    }

    return img
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let base = "ScreenLapse/Assets.xcassets/AppIcon.appiconset"
let fm = FileManager.default

for (name, size) in sizes {
    let img = makeIcon(size: size)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed: \(name)")
        continue
    }
    let url = URL(fileURLWithPath: "\(base)/\(name)")
    try! png.write(to: url)
    print("✓ \(name)")
}
print("Done — icons written to \(base)/")
