// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import AppKit

let canvas = 1024.0
// macOS icon grid: an 824 pt rounded square centred on a 1024 pt canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)

    // Background: deep night gradient.
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.addPath(shape)
    ctx.clip()
    let night = CGGradient(
        colorsSpace: nil,
        colors: [NSColor(srgbRed: 0.16, green: 0.17, blue: 0.27, alpha: 1).cgColor,
                 NSColor(srgbRed: 0.06, green: 0.07, blue: 0.12, alpha: 1).cgColor] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(night, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    // A powerline segment: a bar ending in an arrow, like a shell prompt.
    let midY = 512.0, half = 150.0, left = 192.0, right = 602.0, tip = 130.0
    let segment = CGMutablePath()
    segment.move(to: CGPoint(x: left, y: midY + half))
    segment.addLine(to: CGPoint(x: right, y: midY + half))
    segment.addLine(to: CGPoint(x: right + tip, y: midY))
    segment.addLine(to: CGPoint(x: right, y: midY - half))
    segment.addLine(to: CGPoint(x: left, y: midY - half))
    segment.closeSubpath()
    ctx.saveGState()
    ctx.addPath(segment)
    ctx.clip()
    let glow = CGGradient(
        colorsSpace: nil,
        colors: [NSColor(srgbRed: 0.37, green: 0.92, blue: 0.83, alpha: 1).cgColor,
                 NSColor(srgbRed: 0.22, green: 0.74, blue: 0.97, alpha: 1).cgColor] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(glow, start: CGPoint(x: left, y: midY), end: CGPoint(x: right + tip, y: midY), options: [])
    ctx.restoreGState()

    // "Aa" set in the segment.
    let font = NSFont.monospacedSystemFont(ofSize: 230, weight: .heavy)
    let text = NSAttributedString(string: "Aa", attributes: [
        .font: font, .foregroundColor: NSColor(srgbRed: 0.06, green: 0.07, blue: 0.12, alpha: 1),
    ])
    let bounds = text.boundingRect(with: .zero, options: [.usesLineFragmentOrigin])
    text.draw(at: CGPoint(x: left + (right - left - bounds.width) / 2 + 10, y: midY - bounds.height / 2 + 8))

    // Cursor block after the arrow.
    ctx.setFillColor(NSColor(white: 0.92, alpha: 1).cgColor)
    ctx.fill(CGRect(x: right + tip + 36, y: midY - 110, width: 64, height: 220))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(filePath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
// A fresh folder per run, so overlapping runs can't clobber each other.
let iconset = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for points in [16, 32, 128, 256, 512] {
    try render(size: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try render(size: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}
let resources = root.appending(path: "Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appending(path: "AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    print("iconutil failed with status \(iconutil.terminationStatus)")
    exit(1)
}
print("Wrote Resources/AppIcon.icns")
