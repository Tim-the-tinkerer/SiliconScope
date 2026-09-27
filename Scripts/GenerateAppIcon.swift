#!/usr/bin/env swift
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

func retinaName(_ points: Int) -> String {
    return "icon_\(points)x\(points)" + "@" + "2x.png"
}

func renderIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let margin = s * 0.06
    let corner = s * 0.22
    let rect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let colors = [
        CGColor(srgbRed: 0.07, green: 0.09, blue: 0.16, alpha: 1),
        CGColor(srgbRed: 0.10, green: 0.16, blue: 0.32, alpha: 1),
        CGColor(srgbRed: 0.18, green: 0.16, blue: 0.42, alpha: 1),
        CGColor(srgbRed: 0.08, green: 0.11, blue: 0.22, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.4, 0.75, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    if let highlight = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            highlight,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.midY),
            options: []
        )
    }

    // Grid
    ctx.setStrokeColor(CGColor(srgbRed: 0.35, green: 0.55, blue: 0.95, alpha: 0.12))
    ctx.setLineWidth(max(1, s * 0.006))
    let inset = rect.insetBy(dx: s * 0.14, dy: s * 0.20)
    for i in 0...3 {
        let y = inset.minY + inset.height * CGFloat(i) / 3
        ctx.move(to: CGPoint(x: inset.minX, y: y))
        ctx.addLine(to: CGPoint(x: inset.maxX, y: y))
        ctx.strokePath()
    }

    // Scope wave
    ctx.setStrokeColor(CGColor(srgbRed: 0.40, green: 0.78, blue: 1.0, alpha: 0.95))
    ctx.setLineWidth(max(1.6, s * 0.034))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setShadow(offset: .zero, blur: s * 0.04, color: CGColor(srgbRed: 0.45, green: 0.55, blue: 1, alpha: 0.55))
    let wave = CGMutablePath()
    let steps = 48
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let x = inset.minX + inset.width * t
        let y = inset.midY
            + sin(t * .pi * 2.15) * inset.height * 0.28
            + sin(t * .pi * 6.4) * inset.height * 0.08
        if i == 0 { wave.move(to: CGPoint(x: x, y: y)) }
        else { wave.addLine(to: CGPoint(x: x, y: y)) }
    }
    ctx.addPath(wave)
    ctx.strokePath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Four metric dots: CPU GPU MEM ANE
    let dots: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0.30, 0.64, 1.00, 1),
        (0.24, 0.86, 0.59, 1),
        (0.96, 0.76, 0.30, 1),
        (0.75, 0.52, 0.99, 1),
    ]
    let dotY = rect.minY + s * 0.16
    let spacing = inset.width / 5
    for (i, rgba) in dots.enumerated() {
        let x = inset.minX + spacing * CGFloat(i + 1)
        ctx.setFillColor(CGColor(srgbRed: rgba.0, green: rgba.1, blue: rgba.2, alpha: rgba.3))
        let r = s * 0.028
        ctx.fillEllipse(in: CGRect(x: x - r, y: dotY - r, width: r * 2, height: r * 2))
    }

    ctx.restoreGState()

    ctx.setStrokeColor(CGColor(srgbRed: 0.70, green: 0.82, blue: 1.0, alpha: 0.35))
    ctx.setLineWidth(max(1.0, s * 0.012))
    ctx.addPath(path)
    ctx.strokePath()

    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Could not create image destination for \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        fatalError("Could not write PNG \(url.path)")
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets", isDirectory: true)
let iconset = assets.appendingPathComponent("AppIcon.iconset", isDirectory: true)

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let slots: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

var expectedNames: [String] = []
for slot in slots {
    let name: String
    if slot.scale == 1 {
        name = "icon_\(slot.points)x\(slot.points).png"
    } else {
        name = retinaName(slot.points)
    }
    let px = slot.points * slot.scale
    guard let img = renderIcon(size: px) else {
        fatalError("Failed to render icon size \(px)")
    }
    writePNG(img, to: iconset.appendingPathComponent(name))
    expectedNames.append(name)
    print("  \(name) (\(px)px)")
}

if let master = renderIcon(size: 1024) {
    writePNG(master, to: assets.appendingPathComponent("AppIcon-1024.png"))
}

let written = try FileManager.default.contentsOfDirectory(atPath: iconset.path).sorted()
let expected = Set(expectedNames)
let actual = Set(written)
guard actual == expected, expected.count == 10 else {
    fatalError("Iconset mismatch.\nExpected (\(expected.count)): \(expected.sorted())\nActual (\(actual.count)): \(actual.sorted())")
}

for name in written {
    if name.contains("example.") || !name.hasPrefix("icon_") {
        fatalError("Unexpected icon filename: \(name)")
    }
}

let icnsURL = assets.appendingPathComponent("AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(process.terminationStatus)")
}

print("Wrote \(icnsURL.path) (\(written.count) iconset slots)")
for n in written { print("  OK \(n)") }
