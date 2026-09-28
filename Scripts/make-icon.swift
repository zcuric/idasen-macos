#!/usr/bin/env swift
//
// Renders the Idasen app icon (all sizes) into Resources/AppIcon.iconset.
// Usage: swift Scripts/make-icon.swift
//
import AppKit
import Foundation

let canvas: CGFloat = 1024
let inset: CGFloat = 96 // Big Sur-style margin

func squirclePath(in rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// Draws the icon artwork into the current graphics context, scaled to `size`.
func drawIcon(size: CGFloat) {
    let scale = size / canvas
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.scaleBy(x: scale, y: scale)

    // Background squircle with a soft drop shadow.
    let bodyRect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
    let body = squirclePath(in: bodyRect, radius: 196)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 46, color: NSColor.black.withAlphaComponent(0.32).cgColor)
    NSColor.black.setFill()
    body.fill()
    ctx.restoreGState()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.24, green: 0.46, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.42, green: 0.24, blue: 0.92, alpha: 1),
    ])!
    gradient.draw(in: body, angle: -70)

    // Inner top highlight.
    NSColor.white.withAlphaComponent(0.18).setStroke()
    body.lineWidth = 6
    body.stroke()

    // Vignette at the bottom for depth.
    ctx.saveGState()
    body.addClip()
    let shade = NSGradient(colors: [
        NSColor.black.withAlphaComponent(0.0),
        NSColor.black.withAlphaComponent(0.20),
    ])!
    shade.draw(in: CGRect(x: 0, y: inset, width: canvas, height: 420), angle: -90)
    ctx.restoreGState()

    // Desk surface.
    let deskWidth: CGFloat = 620
    let deskX = (canvas - deskWidth) / 2
    let deskY: CGFloat = 372
    let deskHeight: CGFloat = 58
    let deskRect = CGRect(x: deskX, y: deskY, width: deskWidth, height: deskHeight)
    let desk = squirclePath(in: deskRect, radius: 16)
    NSColor.white.withAlphaComponent(0.97).setFill()
    desk.fill()

    // Desk top edge highlight.
    NSColor.white.setFill()
    squirclePath(
        in: CGRect(x: deskX + 8, y: deskY + deskHeight - 14, width: deskWidth - 16, height: 10),
        radius: 5
    ).fill()

    // Legs with telescoping detail.
    let legWidth: CGFloat = 56
    let legTop = deskY - 8
    let legBottom: CGFloat = 214
    for x in [deskX + 66, deskX + deskWidth - 66 - legWidth] {
        let outer = CGRect(x: x, y: legBottom, width: legWidth, height: legTop - legBottom)
        NSColor.white.withAlphaComponent(0.88).setFill()
        squirclePath(in: outer, radius: 14).fill()

        let inner = CGRect(x: x + 14, y: legBottom - 10, width: legWidth - 28, height: 150)
        NSColor.white.withAlphaComponent(0.55).setFill()
        squirclePath(in: inner, radius: 9).fill()
    }

    // Foot plates.
    for x in [deskX + 46, deskX + deskWidth - 46 - 96] {
        let foot = CGRect(x: x, y: legBottom - 26, width: 96, height: 26)
        NSColor.white.withAlphaComponent(0.92).setFill()
        squirclePath(in: foot, radius: 12).fill()
    }

    // Floor shadow under the desk.
    ctx.saveGState()
    let shadowRect = CGRect(x: deskX - 20, y: legBottom - 54, width: deskWidth + 40, height: 46)
    let shadowPath = NSBezierPath(ovalIn: shadowRect)
    NSColor.black.withAlphaComponent(0.18).setFill()
    shadowPath.fill()
    ctx.restoreGState()

    // Up/down arrow above the desk.
    let arrowX = canvas / 2
    let arrowTop: CGFloat = 806
    let arrowBottom: CGFloat = 522
    let barWidth: CGFloat = 46
    let bar = CGRect(x: arrowX - barWidth / 2, y: arrowBottom + 46, width: barWidth, height: arrowTop - arrowBottom - 92)
    NSColor.white.withAlphaComponent(0.95).setFill()
    squirclePath(in: bar, radius: barWidth / 2).fill()

    let headSize: CGFloat = 92
    let upHead = NSBezierPath()
    upHead.move(to: CGPoint(x: arrowX, y: arrowTop))
    upHead.line(to: CGPoint(x: arrowX - headSize / 2, y: arrowTop - headSize * 0.85))
    upHead.line(to: CGPoint(x: arrowX + headSize / 2, y: arrowTop - headSize * 0.85))
    upHead.close()
    NSColor.white.setFill()
    upHead.fill()

    let downHead = NSBezierPath()
    downHead.move(to: CGPoint(x: arrowX, y: arrowBottom))
    downHead.line(to: CGPoint(x: arrowX - headSize / 2, y: arrowBottom + headSize * 0.85))
    downHead.line(to: CGPoint(x: arrowX + headSize / 2, y: arrowBottom + headSize * 0.85))
    downHead.close()
    NSColor.white.withAlphaComponent(0.92).setFill()
    downHead.fill()

    ctx.restoreGState()
}

func renderPNG(size: Int, to url: URL) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try data.write(to: url)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let entries: [(name: String, pixels: Int)] = [
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

for entry in entries {
    try renderPNG(size: entry.pixels, to: iconset.appendingPathComponent(entry.name))
}

print("Wrote \(entries.count) images to \(iconset.path)")
