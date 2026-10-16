#!/usr/bin/env swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

// Original vector artwork, rendered at each icon resolution without dependencies.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/PauseGuard.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func render(_ size: Int) throws -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 198, yRadius: 198)
    NSColor(calibratedRed: 0.035, green: 0.075, blue: 0.14, alpha: 1).setFill(); tile.fill()
    NSGradient(starting: NSColor(calibratedRed: 0.09, green: 0.19, blue: 0.29, alpha: 1),
        ending: NSColor(calibratedRed: 0.025, green: 0.045, blue: 0.10, alpha: 1))!.draw(in: tile, angle: -70)
    // A quiet breathing ring, not a protective shield or warning mark.
    for (diameter, alpha, width): (CGFloat, CGFloat, CGFloat) in [(628, 0.045, 44), (612, 0.10, 22), (604, 0.38, 5)] {
        let ring = NSBezierPath(ovalIn: NSRect(x: (1024-diameter)/2, y: (1024-diameter)/2, width: diameter, height: diameter))
        NSColor(calibratedRed: 0.40, green: 0.96, blue: 0.78, alpha: alpha).setStroke()
        ring.lineWidth = width; ring.stroke()
    }
    for x: CGFloat in [365, 549] {
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: 332, width: 110, height: 360), xRadius: 40, yRadius: 40)
        NSGradient(starting: NSColor(calibratedRed: 0.76, green: 1, blue: 0.88, alpha: 1),
            ending: NSColor(calibratedRed: 0.30, green: 0.88, blue: 0.71, alpha: 1))!.draw(in: bar, angle: -90)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = "icon_\(points)x\(points)" + (factor == 2 ? "@2x" : "") + ".png"
        try render(points * factor).write(to: iconset.appendingPathComponent(name))
    }
}
try render(1024).write(to: root.appendingPathComponent("Resources/PauseGuard-icon.png"))
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/PauseGuard.icns").path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Generated Resources/PauseGuard.icns and PauseGuard-icon.png")
