import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PauseGuardImages

func pixels(_ image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return true
    }
    #expect(rendered)
    return bytes
}

@Test func testNoEnabledThemesUsesDefault() {
    let asset = ImageAsset(fileName: "a.png", width: 1, height: 1, thumbnailName: "t.png")
    #expect(ImageSelector.select(themes: [BreakTheme(name: "disabled", enabled: false, imageIDs: [asset.id])], assets: [asset], previous: nil) == nil)
    #expect(ImageSelector.select(themes: [], assets: [asset], previous: nil) == nil)
    #expect(ImageSelector.select(themes: [BreakTheme(name: "missing", imageIDs: [UUID()])], assets: [asset], previous: nil) == nil)
}

@Test func testSelectionAvoidsImmediateRepeatWhenPossible() throws {
    let a = ImageAsset(fileName: "a.png", width: 1, height: 1, thumbnailName: "a-thumb.png")
    let b = ImageAsset(fileName: "b.png", width: 1, height: 1, thumbnailName: "b-thumb.png")
    let themes = [BreakTheme(name: "A", imageIDs: [a.id, b.id, UUID()])]
    var last = try #require(ImageSelector.select(themes: themes, assets: [a, b], previous: nil))
    for _ in 0..<30 {
        let next = try #require(ImageSelector.select(themes: themes, assets: [a, b], previous: last))
        #expect(next.assets.first?.id != last.assets.first?.id)
        #expect(Set(next.assets.map(\.id)).count == 2)
        last = next
    }
}

@Test func testFiveLayoutsRender() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let library = try AssetLibrary(rootURL: root.appendingPathComponent("library"))
    let urls = try (0..<4).map { index in
        try fixture(root, name: "\(index).png", color: CGColor(red: CGFloat(index) / 3, green: 0.8, blue: 0.2, alpha: 1))
    }
    let assets = try library.importImages(urls)
    var outputs: [Data] = []
    for mode in LayoutMode.concreteCases {
        let image = try Compositor.render(selection: Selection(layoutMode: mode, assets: assets), size: CGSize(width: 320, height: 200), libraryURL: library.rootURL)
        #expect(image.width == 320 && image.height == 200)
        let data = try pixels(image)
        #expect(Set(stride(from: 0, to: data.count, by: 4).map { data[$0] }).count > 12)
        outputs.append(Data(data))
        if let folder = ProcessInfo.processInfo.environment["PAUSEGUARD_PREVIEW_DIR"] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            let destination = try #require(CGImageDestinationCreateWithURL(URL(fileURLWithPath: folder).appendingPathComponent("\(mode.rawValue).png") as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil); #expect(CGImageDestinationFinalize(destination))
        }
    }
    #expect(Set(outputs).count == 5)
}

@Test func testSingleImageFallbackAndSafeCountdownCenter() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let library = try AssetLibrary(rootURL: root.appendingPathComponent("library"))
    let assets = try library.importImages([fixture(root, color: CGColor(gray: 1, alpha: 1))])
    for mode in LayoutMode.concreteCases {
        let image = try Compositor.render(selection: Selection(layoutMode: mode, assets: assets), size: CGSize(width: 320, height: 200), libraryURL: library.rootURL)
        let data = try pixels(image); let offset = (100 * 320 + 160) * 4
        #expect(max(data[offset], data[offset + 1], data[offset + 2]) < 95)
        #expect(data[offset + 3] == 255)
    }
}

@Test func testOversizedImageIsDownsampled() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let library = try AssetLibrary(rootURL: root.appendingPathComponent("library"))
    let assets = try library.importImages([fixture(root, width: 6000, height: 200)])
    let asset = try #require(assets.first)
    let decoded = try ImageDecoding.load(asset, libraryURL: library.rootURL, maxPixel: 900)
    #expect(decoded.width == 900 && decoded.height == 30)
    let image = try Compositor.render(selection: Selection(layoutMode: .hero, assets: assets), size: CGSize(width: 10000, height: 1000), libraryURL: library.rootURL)
    #expect(image.width == 4096 && image.height == 409)
    #expect(throws: ImageLibraryError.self) {
        try Compositor.render(selection: Selection(layoutMode: .hero, assets: assets), size: CGSize(width: CGFloat.infinity, height: 100), libraryURL: library.rootURL)
    }
}

@Test func testCacheEvicts() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let url = try fixture(root)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let cache = BackgroundCache(maximumCount: 2, maximumBytes: 100_000)
    cache.insert(image, forKey: "a"); cache.insert(image, forKey: "b")
    #expect(cache.image(forKey: "a") != nil)
    cache.insert(image, forKey: "c")
    #expect(cache.image(forKey: "b") == nil)
    #expect(cache.image(forKey: "a") != nil)
    let small = BackgroundCache(maximumCount: 8, maximumBytes: 40_000)
    small.insert(image, forKey: "a"); small.insert(image, forKey: "b")
    #expect(small.image(forKey: "a") == nil)
    #expect(small.image(forKey: "b") != nil)
    let tiny = BackgroundCache(maximumBytes: 1)
    tiny.insert(image, forKey: "a")
    #expect(tiny.image(forKey: "a") == nil)
}

@Test func testRandomLayoutResolvesAndAvoidsPrevious() throws {
    let asset = ImageAsset(fileName: "a.png", width: 1, height: 1, thumbnailName: "t.png")
    let theme = BreakTheme(name: "Random", imageIDs: [asset.id], layoutMode: .random)
    var last = Selection(themeID: theme.id, layoutMode: .hero, assets: [asset])
    for _ in 0..<30 {
        let next = try #require(ImageSelector.select(themes: [theme], assets: [asset], previous: last))
        #expect(LayoutMode.concreteCases.contains(next.layoutMode))
        #expect(next.layoutMode != last.layoutMode)
        last = next
    }
}
