#!/usr/bin/env swift
//
//  artwork.swift — WriteBetter brand artwork generator
//
//  Renders every raster asset the product ships from ONE source of geometry:
//  the "Caret Ascend" mark defined in scratchpad/DESIGN-BRIEF.md §2.2, in the
//  palette from §3. The app icon, the menu-bar template, the in-app logo mark
//  and the DMG background all come out of this file so they cannot drift apart.
//
//  Deterministic and re-runnable: same input -> byte-identical output.
//
//  Usage:
//    swift scripts/artwork.swift appicon  <out-dir>            # .appiconset PNGs
//    swift scripts/artwork.swift menubar  <out-dir>            # 18/36 template PNGs
//    swift scripts/artwork.swift logomark <out-dir>            # 256/512 colour PNGs
//    swift scripts/artwork.swift iconset  <out-dir.iconset>    # for `iconutil -c icns`
//    swift scripts/artwork.swift dmgbg    <out-dir> [--warning]
//
//  Coordinate convention: the whole file works in the design brief's top-left
//  origin, y-down, 1024x1024 space. The CTM is flipped exactly once, in
//  render(), and never again.
//

import AppKit
import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Colour

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: sRGB,
        components: [
            CGFloat((value >> 16) & 0xFF) / 255,
            CGFloat((value >> 8) & 0xFF) / 255,
            CGFloat(value & 0xFF) / 255,
            alpha,
        ]
    )!
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(
        colorsSpace: sRGB,
        colors: stops.map { hex($0.0, $0.1) } as CFArray,
        locations: stops.map { $0.2 }
    )!
}

let gradientEdges: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]

// DESIGN-BRIEF §3.1
enum Ink {
    static let tileA: UInt32 = 0x1B1F3D
    static let tileB: UInt32 = 0x0E1226
    static let tileC: UInt32 = 0x05060E
    static let accent: UInt32 = 0x7C6BFF
    static let gradientEnd: UInt32 = 0x37D3E8
    static let caretA: UInt32 = 0xFFFFFF
    static let caretB: UInt32 = 0xEDEBFF
    static let caretC: UInt32 = 0xB9AEFF
    static let textPrimary: UInt32 = 0xF2F4F8
    static let textSecondary: UInt32 = 0xA8B0BF
    static let warning: UInt32 = 0xF5B841
}

// MARK: - Raster plumbing

func render(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage {
    guard
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { fatalError("could not create a \(width)x\(height) bitmap context") }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    // The one and only flip: from here down, y grows downward.
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)

    body(ctx)

    guard let image = ctx.makeImage() else { fatalError("makeImage failed") }
    return image
}

func writePNG(_ image: CGImage, to url: URL, dpi: Int) {
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not open \(url.path) for writing") }
    let properties: [CFString: Any] = [
        kCGImagePropertyDPIWidth: dpi,
        kCGImagePropertyDPIHeight: dpi,
    ]
    CGImageDestinationAddImage(dest, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
    FileHandle.standardError.write("  wrote \(url.lastPathComponent)\n".data(using: .utf8)!)
}

// MARK: - Layer 1: tile (DESIGN-BRIEF §2.2 Layer 1)

let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 185

/// macOS Big Sur+ icon silhouette: a *continuous* (squircle) rounded rect, not a
/// circular-corner one. SwiftUI owns the only correct implementation of that
/// curve on the platform, so we borrow its path rather than approximating it.
func tilePath(inset: CGFloat = 0) -> CGPath {
    RoundedRectangle(cornerRadius: tileRadius - inset, style: .continuous)
        .path(in: tileRect.insetBy(dx: inset, dy: inset))
        .cgPath
}

func drawTile(_ ctx: CGContext) {
    let path = tilePath()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(Ink.tileA, 1, 0.00), (Ink.tileB, 1, 0.42), (Ink.tileC, 1, 1.00)]),
        start: CGPoint(x: 152, y: 100),
        end: CGPoint(x: 872, y: 924),
        options: gradientEdges
    )
    ctx.drawRadialGradient(
        gradient([(Ink.accent, 0.42, 0.0), (Ink.accent, 0.0, 1.0)]),
        startCenter: CGPoint(x: 512, y: 430), startRadius: 0,
        endCenter: CGPoint(x: 512, y: 430), endRadius: 470,
        options: []
    )
    ctx.restoreGState()

    // Rim highlight — light catching the top edge of the tile.
    ctx.saveGState()
    ctx.addPath(tilePath(inset: 2))
    ctx.setLineWidth(3)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(0xFFFFFF, 0.30, 0.00), (0xFFFFFF, 0.00, 0.45)]),
        start: CGPoint(x: 0, y: 100),
        end: CGPoint(x: 0, y: 924),
        options: gradientEdges
    )
    ctx.restoreGState()

    // Outer edge — separates the tile from a light desktop.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(1)
    ctx.setStrokeColor(hex(0x000000, 0.35))
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Layer 2: caret

let caretPath: CGPath = {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 296, y: 604))
    p.addLine(to: CGPoint(x: 512, y: 388))
    p.addLine(to: CGPoint(x: 728, y: 604))
    return p
}()

func drawCaret(_ ctx: CGContext, lineWidth: CGFloat, shadow: Bool, monochrome: Bool) {
    if shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 46, color: hex(Ink.accent, 0.55))
        ctx.addPath(caretPath)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(hex(Ink.caretB))
        ctx.strokePath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(caretPath)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    if monochrome {
        ctx.setStrokeColor(hex(0x000000))
        ctx.strokePath()
    } else {
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(
            gradient([(Ink.caretA, 1, 0.00), (Ink.caretB, 1, 0.55), (Ink.caretC, 1, 1.00)]),
            start: CGPoint(x: 296, y: 388),
            end: CGPoint(x: 728, y: 604),
            options: gradientEdges
        )
    }
    ctx.restoreGState()
}

// MARK: - Layer 3: baseline bar

let barCentreY: CGFloat = 720
let barLeft: CGFloat = 330
let barWidth: CGFloat = 364

func drawBar(_ ctx: CGContext, height: CGFloat, monochrome: Bool) {
    let rect = CGRect(x: barLeft, y: barCentreY - height / 2, width: barWidth, height: height)
    let path = CGPath(
        roundedRect: rect, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    if monochrome {
        ctx.setFillColor(hex(0x000000))
        ctx.fillPath()
    } else {
        ctx.clip()
        ctx.drawLinearGradient(
            gradient([(Ink.accent, 1, 0.0), (Ink.gradientEnd, 1, 1.0)]),
            start: CGPoint(x: barLeft, y: barCentreY),
            end: CGPoint(x: barLeft + barWidth, y: barCentreY),
            options: gradientEdges
        )
    }
    ctx.restoreGState()
}

// MARK: - Layer 4: spark

let sparkCentre = CGPoint(x: 762, y: 350)
let sparkRadius: CGFloat = 74

/// Four quadratic Béziers, tip to tip, each with its control point at the
/// centre — the classic concave four-point twinkle.
let sparkPath: CGPath = {
    let c = sparkCentre
    let n = CGPoint(x: c.x, y: c.y - sparkRadius)
    let e = CGPoint(x: c.x + sparkRadius, y: c.y)
    let s = CGPoint(x: c.x, y: c.y + sparkRadius)
    let w = CGPoint(x: c.x - sparkRadius, y: c.y)
    let p = CGMutablePath()
    p.move(to: n)
    p.addQuadCurve(to: e, control: c)
    p.addQuadCurve(to: s, control: c)
    p.addQuadCurve(to: w, control: c)
    p.addQuadCurve(to: n, control: c)
    p.closeSubpath()
    return p
}()

func drawSpark(_ ctx: CGContext, glow: Bool) {
    ctx.saveGState()
    if glow {
        ctx.setShadow(offset: .zero, blur: 30, color: hex(Ink.gradientEnd, 0.60))
    }
    ctx.addPath(sparkPath)
    ctx.setFillColor(hex(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()
}

// MARK: - Renditions

/// Full app icon: tile + caret + bar + spark. Below 32pt the spark stops being
/// legible, so it is dropped and the caret is thickened (DESIGN-BRIEF §2.2).
func drawAppIcon(_ ctx: CGContext, pixels: CGFloat, simplified: Bool) {
    ctx.saveGState()
    ctx.scaleBy(x: pixels / 1024, y: pixels / 1024)
    drawTile(ctx)
    drawCaret(ctx, lineWidth: simplified ? 118 : 104, shadow: true, monochrome: false)
    drawBar(ctx, height: 68, monochrome: false)
    if !simplified { drawSpark(ctx, glow: true) }
    ctx.restoreGState()
}

/// The mark without its tile, trimmed to its own bounding box and centred in a
/// square. `monochrome` gives the menu-bar template rendition (caret + bar only,
/// solid black, heavier weight so it survives 18pt).
func drawGlyph(_ ctx: CGContext, pixels: CGFloat, monochrome: Bool, margin: CGFloat) {
    let caretWidth: CGFloat = monochrome ? 118 : 104
    let barHeight: CGFloat = monochrome ? 78 : 68

    var minX = 296 - caretWidth / 2
    var maxX = 728 + caretWidth / 2
    var minY = 388 - caretWidth / 2
    var maxY = 604 + caretWidth / 2
    minX = min(minX, barLeft)
    maxX = max(maxX, barLeft + barWidth)
    minY = min(minY, barCentreY - barHeight / 2)
    maxY = max(maxY, barCentreY + barHeight / 2)
    if !monochrome {
        minX = min(minX, sparkCentre.x - sparkRadius)
        maxX = max(maxX, sparkCentre.x + sparkRadius)
        minY = min(minY, sparkCentre.y - sparkRadius)
        maxY = max(maxY, sparkCentre.y + sparkRadius)
    }

    let boxWidth = maxX - minX
    let boxHeight = maxY - minY
    let scale = (pixels * (1 - 2 * margin)) / max(boxWidth, boxHeight)

    ctx.saveGState()
    ctx.translateBy(x: (pixels - boxWidth * scale) / 2, y: (pixels - boxHeight * scale) / 2)
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -minX, y: -minY)
    drawCaret(ctx, lineWidth: caretWidth, shadow: false, monochrome: monochrome)
    drawBar(ctx, height: barHeight, monochrome: monochrome)
    if !monochrome { drawSpark(ctx, glow: true) }
    ctx.restoreGState()
}

// MARK: - Text

func drawText(
    _ ctx: CGContext, _ string: String, centredAt: CGPoint, size: CGFloat,
    weight: NSFont.Weight, colour: UInt32, alpha: CGFloat = 1, tracking: CGFloat = 0
) {
    let saved = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    defer { NSGraphicsContext.current = saved }

    let components = hex(colour, alpha).components ?? [1, 1, 1, 1]
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(
            srgbRed: components[0], green: components[1], blue: components[2], alpha: alpha),
        .kern: tracking,
    ]
    let attributed = NSAttributedString(string: string, attributes: attributes)
    let bounds = attributed.size()
    attributed.draw(
        at: CGPoint(x: centredAt.x - bounds.width / 2, y: centredAt.y - bounds.height / 2))
}

// MARK: - DMG background (DESIGN-BRIEF §2.2 "DMG background")

let dmgWindow = CGSize(width: 660, height: 400)
/// Must match `icon_locations` in scripts/dmg_settings.py.
let dmgIconY: CGFloat = 196

func drawDMGBackground(_ ctx: CGContext, scale: CGFloat, warning: Bool) {
    let w = dmgWindow.width
    let h = dmgWindow.height

    ctx.saveGState()
    ctx.scaleBy(x: scale, y: scale)

    // Tile fill + bloom, full bleed, proportionally mapped off the 1024 tile.
    ctx.saveGState()
    ctx.addRect(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(Ink.tileA, 1, 0.00), (Ink.tileB, 1, 0.42), (Ink.tileC, 1, 1.00)]),
        start: CGPoint(x: w * 0.148, y: h * 0.098),
        end: CGPoint(x: w * 0.852, y: h * 0.902),
        options: gradientEdges
    )
    ctx.drawRadialGradient(
        gradient([(Ink.accent, 0.26, 0.0), (Ink.accent, 0.0, 1.0)]),
        startCenter: CGPoint(x: w * 0.50, y: h * 0.42), startRadius: 0,
        endCenter: CGPoint(x: w * 0.50, y: h * 0.42), endRadius: w * 0.52,
        options: []
    )
    ctx.restoreGState()

    // Brand lockup: glyph at 22% width / 17% height, wordmark beneath it.
    let brandX = w * 0.22
    let brandY = h * 0.17
    let glyphBox: CGFloat = 44
    ctx.saveGState()
    ctx.translateBy(x: brandX - glyphBox / 2, y: brandY - glyphBox / 2)
    drawGlyph(ctx, pixels: glyphBox, monochrome: false, margin: 0.04)
    ctx.restoreGState()
    drawText(
        ctx, "WriteBetter",
        centredAt: CGPoint(x: brandX, y: brandY + glyphBox / 2 + 15),
        size: 17, weight: .semibold, colour: Ink.textPrimary, tracking: -0.34)

    // Drag arrow, sitting between the two icon slots.
    ctx.saveGState()
    ctx.setStrokeColor(hex(Ink.accent, 0.40))
    ctx.setLineWidth(9)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let shaft = CGMutablePath()
    shaft.move(to: CGPoint(x: 268, y: dmgIconY))
    shaft.addLine(to: CGPoint(x: 388, y: dmgIconY))
    ctx.addPath(shaft)
    ctx.strokePath()
    let head = CGMutablePath()
    head.move(to: CGPoint(x: 370, y: dmgIconY - 20))
    head.addLine(to: CGPoint(x: 392, y: dmgIconY))
    head.addLine(to: CGPoint(x: 370, y: dmgIconY + 20))
    ctx.addPath(head)
    ctx.strokePath()
    ctx.restoreGState()

    // Honest Gatekeeper note — only on builds that are not notarized.
    if warning {
        drawText(
            ctx, "This build is not notarized by Apple.",
            centredAt: CGPoint(x: w / 2, y: h - 62),
            size: 11, weight: .semibold, colour: Ink.warning, tracking: 0.1)
        drawText(
            ctx,
            "If macOS says WriteBetter is damaged, it isn’t — open System Settings ▸ Privacy & Security,",
            centredAt: CGPoint(x: w / 2, y: h - 44),
            size: 10.5, weight: .regular, colour: Ink.textSecondary, alpha: 0.92)
        drawText(
            ctx, "scroll to Security, and click “Open Anyway”. You only do this once.",
            centredAt: CGPoint(x: w / 2, y: h - 28),
            size: 10.5, weight: .regular, colour: Ink.textSecondary, alpha: 0.92)
    }

    ctx.restoreGState()
}

// MARK: - Entry point

func die(_ message: String) -> Never {
    FileHandle.standardError.write("artwork.swift: \(message)\n".data(using: .utf8)!)
    exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
    die("usage: artwork.swift <appicon|menubar|logomark|iconset|dmgbg> <out-dir> [--warning]")
}
let mode = arguments[0]
let outDir = URL(fileURLWithPath: arguments[1], isDirectory: true)
let wantsWarning = arguments.contains("--warning")

/// (point size, scale) pairs Apple asks for in a macOS .appiconset, mapped to
/// the `icon_NxN[@2x].png` filenames `iconutil` also understands.
let macIconVariants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

func iconFilename(points: Int, scale: Int) -> String {
    scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
}

func emitIcons(into directory: URL) {
    for variant in macIconVariants {
        let pixels = variant.points * variant.scale
        let image = render(width: pixels, height: pixels) { ctx in
            drawAppIcon(ctx, pixels: CGFloat(pixels), simplified: variant.points <= 32)
        }
        writePNG(
            image,
            to: directory.appendingPathComponent(
                iconFilename(points: variant.points, scale: variant.scale)),
            dpi: 72 * variant.scale)
    }
}

switch mode {
case "appicon", "iconset":
    emitIcons(into: outDir)

case "menubar":
    for (pixels, scale) in [(18, 1), (36, 2)] {
        let image = render(width: pixels, height: pixels) { ctx in
            drawGlyph(ctx, pixels: CGFloat(pixels), monochrome: true, margin: 0.08)
        }
        writePNG(
            image, to: outDir.appendingPathComponent("menubar-\(pixels).png"), dpi: 72 * scale)
    }

case "logomark":
    for (pixels, scale) in [(256, 1), (512, 2)] {
        let image = render(width: pixels, height: pixels) { ctx in
            drawGlyph(ctx, pixels: CGFloat(pixels), monochrome: false, margin: 0.04)
        }
        writePNG(
            image, to: outDir.appendingPathComponent("logomark-\(pixels).png"), dpi: 72 * scale)
    }

case "dmgbg":
    for (name, scale) in [("background.png", CGFloat(1)), ("background@2x.png", CGFloat(2))] {
        let image = render(
            width: Int(dmgWindow.width * scale), height: Int(dmgWindow.height * scale)
        ) { ctx in
            drawDMGBackground(ctx, scale: scale, warning: wantsWarning)
        }
        writePNG(
            image, to: outDir.appendingPathComponent(name), dpi: Int(72 * scale))
    }

default:
    die("unknown mode '\(mode)'")
}
