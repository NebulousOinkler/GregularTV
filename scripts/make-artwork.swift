// Generates the app icon and Top Shelf images into the asset catalog.
//
//     swift scripts/make-artwork.swift
//
// Everything is drawn here: the Gregular wordmark on a deep gradient, with a
// slim pill of classic TV colour bars as the one accent.
// No artwork comes from the Jellyfin server, so the Top Shelf reveals nothing
// about the library (PLAN.md §3). Edit the drawing functions to restyle, then rerun.

import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

let catalog = URL(fileURLWithPath: "App/GregularTV/Assets.xcassets")
let brand = catalog.appendingPathComponent("App Icon & Top Shelf Image.brandassets")

// MARK: - Drawing

/// 75% SMPTE colour bars.
let barColors: [(CGFloat, CGFloat, CGFloat)] = [
    (0.75, 0.75, 0.75), (0.75, 0.75, 0), (0, 0.75, 0.75), (0, 0.75, 0), (0.75, 0, 0.75), (0.75, 0, 0), (0, 0, 0.75),
]
/// The icon's gradient: deep indigo at the top to near-black navy at the bottom.
let gradientTop = CGColor(srgbRed: 0.16, green: 0.17, blue: 0.36, alpha: 1)
let gradientBottom = CGColor(srgbRed: 0.04, green: 0.05, blue: 0.12, alpha: 1)

func font(size: CGFloat, weight: NSFont.Weight, rounded: Bool) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard rounded, let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

/// The font size at which `text` is `width` wide.
func size(toFit text: String, width: CGFloat, weight: NSFont.Weight, rounded: Bool) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [.font: font(size: 100, weight: weight, rounded: rounded)]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    return 100 * width / CTLineGetBoundsWithOptions(line, .useGlyphPathBounds).width
}

func drawText(_ ctx: CGContext, _ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1,
              rounded: Bool = false, shadow: CGFloat = 0.7,
              centerX: CGFloat? = nil, x: CGFloat = 0, centerY: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font(size: size, weight: weight, rounded: rounded),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: alpha),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    // Image bounds are measured from the context's current text position,
    // which the previous draw moved, so reset it first.
    ctx.textPosition = .zero
    let bounds = CTLineGetImageBounds(line, ctx)
    let originX = centerX.map { $0 - bounds.width / 2 - bounds.minX } ?? x - bounds.minX
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.04), blur: size * 0.15, color: CGColor(gray: 0, alpha: shadow))
    ctx.textPosition = CGPoint(x: originX, y: centerY - bounds.height / 2 - bounds.minY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

/// The deep gradient behind everything, with a soft glow where the wordmark sits.
func drawBackdrop(_ ctx: CGContext, in rect: CGRect, glowAt glow: CGPoint) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)
    let gradient = CGGradient(colorsSpace: space, colors: [gradientTop, gradientBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    let light = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: 0.45, green: 0.5, blue: 1, alpha: 0.22),
                                                        CGColor(srgbRed: 0.45, green: 0.5, blue: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(light, startCenter: glow, startRadius: 0, endCenter: glow, endRadius: rect.width * 0.55, options: [])
}

/// The seven colour bars as one slim pill.
func drawBarPill(_ ctx: CGContext, in rect: CGRect) {
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
    ctx.clip()
    let full = barColors.map { ($0.0 / 0.75, $0.1 / 0.75, $0.2 / 0.75) }   // 100% bars: brighter, cleaner
    let width = rect.width / CGFloat(full.count)
    for (i, c) in full.enumerated() {
        ctx.setFillColor(CGColor(srgbRed: c.0 * 0.85, green: c.1 * 0.85, blue: c.2 * 0.85, alpha: 1))
        ctx.fill(CGRect(x: rect.minX + CGFloat(i) * width, y: rect.minY, width: width + 1, height: rect.height))
    }
    ctx.restoreGState()
}

// The icon's layers, back to front. Wordmark and pill sit inside the middle
// 80% so nothing is cut off when the icon is focused and grows.
let wordmarkWidth: CGFloat = 0.74    // of the icon's width
let wordmarkCenterY: CGFloat = 0.55  // of the icon's height

/// Icon back layer: the gradient, full bleed.
func iconBack(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    drawBackdrop(ctx, in: CGRect(x: 0, y: 0, width: w, height: h), glowAt: CGPoint(x: w / 2, y: h * wordmarkCenterY))
}

/// Icon middle layer: the colour-bar pill under the wordmark.
func iconMiddle(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let width = w * 0.3, height = h * 0.045
    drawBarPill(ctx, in: CGRect(x: (w - width) / 2, y: h * 0.26, width: width, height: height))
}

/// Icon front layer: the wordmark on transparency, so it floats in parallax.
/// Just "Gregular": the Home Screen shows the full name under the icon.
func iconFront(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let size = size(toFit: "Gregular", width: w * wordmarkWidth, weight: .bold, rounded: true)
    drawText(ctx, "Gregular", size: size, weight: .bold, rounded: true, shadow: 0.35,
             centerX: w / 2, centerY: h * wordmarkCenterY)
}

/// Top Shelf: the icon's look, wide. Everything is centred, because tvOS
/// enlarges the image and crops its sides by different amounts.
func topShelf(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    drawBackdrop(ctx, in: CGRect(x: 0, y: 0, width: w, height: h), glowAt: CGPoint(x: w / 2, y: h * 0.6))
    drawText(ctx, "Gregular TV", size: h * 0.2, weight: .bold, rounded: true, shadow: 0.35, centerX: w / 2, centerY: h * 0.62)
    let pill = h * 0.4
    drawBarPill(ctx, in: CGRect(x: (w - pill) / 2, y: h * 0.44, width: pill, height: h * 0.026))
    drawText(ctx, "We now return to your Gregular programming.", size: h * 0.055, weight: .medium, alpha: 0.7,
             rounded: true, shadow: 0, centerX: w / 2, centerY: h * 0.33)
}

// MARK: - Files

func png(width: Int, height: Int, _ draw: (CGContext, CGFloat, CGFloat) -> Void) -> Data {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx, CGFloat(width), CGFloat(height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

func write(_ json: String, to dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

let info = #""info" : { "author" : "xcode", "version" : 1 }"#

/// An image set with one PNG per scale.
func imageSet(_ dir: URL, name: String, size: (Int, Int), scales: [Int],
              _ draw: @escaping (CGContext, CGFloat, CGFloat) -> Void) throws {
    let entries = scales.map { s in #"{ "filename" : "\#(name)@\#(s)x.png", "idiom" : "tv", "scale" : "\#(s)x" }"# }
    try write(#"{ "images" : [ \#(entries.joined(separator: ", ")) ], \#(info) }"#, to: dir)
    for s in scales {
        try png(width: size.0 * s, height: size.1 * s, draw).write(to: dir.appendingPathComponent("\(name)@\(s)x.png"))
    }
}

/// A layered icon: front floats over middle, over back.
func imageStack(_ name: String, size: (Int, Int), scales: [Int]) throws {
    let stack = brand.appendingPathComponent("\(name).imagestack")
    let layers = [("Front", iconFront), ("Middle", iconMiddle), ("Back", iconBack)]
    let entries = layers.map { #"{ "filename" : "\#($0.0).imagestacklayer" }"# }.joined(separator: ", ")
    try write(#"{ "layers" : [ \#(entries) ], \#(info) }"#, to: stack)
    for (layer, draw) in layers {
        let dir = stack.appendingPathComponent("\(layer).imagestacklayer")
        try write("{ \(info) }", to: dir)
        try imageSet(dir.appendingPathComponent("Content.imageset"), name: layer.lowercased(), size: size, scales: scales, draw)
    }
}

try write("{ \(info) }", to: catalog)
try write("""
{ "assets" : [
    { "filename" : "App Icon - App Store.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "1280x768" },
    { "filename" : "App Icon.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "400x240" },
    { "filename" : "Top Shelf Image Wide.imageset", "idiom" : "tv", "role" : "top-shelf-image-wide", "size" : "2320x720" },
    { "filename" : "Top Shelf Image.imageset", "idiom" : "tv", "role" : "top-shelf-image", "size" : "1920x720" }
  ], \(info) }
""", to: brand)
try imageStack("App Icon", size: (400, 240), scales: [1, 2])
try imageStack("App Icon - App Store", size: (1280, 768), scales: [1])
try imageSet(brand.appendingPathComponent("Top Shelf Image.imageset"), name: "top-shelf",
             size: (1920, 720), scales: [1, 2], topShelf)
try imageSet(brand.appendingPathComponent("Top Shelf Image Wide.imageset"), name: "top-shelf-wide",
             size: (2320, 720), scales: [1, 2], topShelf)
print("Artwork written to \(brand.path)")
