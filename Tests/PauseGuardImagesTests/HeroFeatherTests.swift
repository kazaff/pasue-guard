import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PauseGuardImages

private func solidFixture(_ root: URL, name: String, red: CGFloat, blue: CGFloat) throws -> URL {
    let context = try #require(CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8,
        bytesPerRow: 480, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: red, green: 0, blue: blue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
    let url = root.appendingPathComponent(name)
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

// Catches abutting tiles, a black seam overlay, and feathering that dims the outer photos.
@Test func testHeroBlendsPhotoColorsGraduallyWithoutDarkening() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let library = try AssetLibrary(rootURL: root.appendingPathComponent("library"))
    let assets = try library.importImages([
        solidFixture(root, name: "red.png", red: 1, blue: 0),
        solidFixture(root, name: "blue.png", red: 0, blue: 1)
    ])
    // Decode references independently of Compositor; PNG profiles can change DeviceRGB channels.
    let colors = try assets.map { Array(try pixels(ImageDecoding.load($0, libraryURL: library.rootURL, maxPixel: 400)).prefix(4)) }
    for mode in [LayoutMode.hero, .random] {
        let image = try Compositor.render(selection: Selection(layoutMode: mode, assets: assets),
            size: CGSize(width: 400, height: 160), libraryURL: library.rootURL)
        let bytes = try pixels(image)
        let row = (0..<400).map { x in Array(bytes[((80 * 400 + x) * 4)..<((80 * 400 + x) * 4 + 4)]) }
        let join = Array(row[248...336])
        let jumps = zip(join, join.dropFirst()).map { abs(Int($0[0]) - Int($1[0])) + abs(Int($0[2]) - Int($1[2])) }
        #expect(jumps.max()! < 20, "\(mode): no abrupt adjacent-pixel color jump")
        #expect(join.filter { $0[0] > 30 && $0[2] > 30 }.count > 25, "\(mode): broad band of mixed photo colors")
        #expect(zip(join, join.dropFirst()).allSatisfy { Int($1[0]) <= Int($0[0]) + 1 && Int($1[2]) >= Int($0[2]) - 1 }, "\(mode): monotone crossfade")
        #expect(row.allSatisfy { pixel in
            Int(pixel[0]) + Int(pixel[2]) >= min(Int(colors[0][0]) + Int(colors[0][2]), Int(colors[1][0]) + Int(colors[1][2])) - 2
                && Int(pixel[1]) >= Int(min(colors[0][1], colors[1][1])) - 1
                && Int(pixel[1]) <= Int(max(colors[0][1], colors[1][1])) + 1 && pixel[3] == 255
        }, "\(mode): no black dip or tint")
        #expect(zip(row[80], colors[0]).allSatisfy { abs(Int($0) - Int($1)) <= 1 }
            && zip(row[380], colors[1]).allSatisfy { abs(Int($0) - Int($1)) <= 1 }, "\(mode): opaque outer photo colors")
        if let folder = ProcessInfo.processInfo.environment["PAUSEGUARD_HERO_PREVIEW_DIR"] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(mode.rawValue).png")
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil); #expect(CGImageDestinationFinalize(destination))
        }
    }
}

// Missing auxiliary files must behave like a single photo, including narrow canvases.
@Test func testHeroSingleAndMissingAuxiliaryKeepPhotoAcrossCanvas() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let library = try AssetLibrary(rootURL: root.appendingPathComponent("library"))
    let assets = try library.importImages([solidFixture(root, name: "red.png", red: 1, blue: 0)])
    let missing = ImageAsset(fileName: "missing.png", width: 120, height: 80, thumbnailName: "missing-thumb.png")
    let color = Array(try pixels(ImageDecoding.load(assets[0], libraryURL: library.rootURL, maxPixel: 400)).prefix(4))
    for selected in [assets, assets + [missing]] {
        for width in [1, 2, 400] {
            let image = try Compositor.render(selection: Selection(layoutMode: .hero, assets: selected),
                size: CGSize(width: width, height: 8), libraryURL: library.rootURL)
            let bytes = try pixels(image)
            #expect(stride(from: 0, to: bytes.count, by: 4).allSatisfy {
                zip(bytes[$0..<($0 + 4)], color).allSatisfy { abs(Int($0) - Int($1)) <= 1 }
            }, "single/missing auxiliary photo retains its color at width \(width)")
        }
    }
}
