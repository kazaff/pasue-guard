import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import PauseGuardImages

@Test func testHugeDeclaredDimensionsAreRejectedWithoutDecode() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let url = try fixture(root)
    var bytes = try Data(contentsOf: url)
    // PNG IHDR 20,000 x 20,000 (400 MP); CRC ensures rejection respects dimensions,
    // rather than depending on a damaged file checksum.
    bytes.replaceSubrange(16..<20, with: [0, 0, 0x4e, 0x20])
    bytes.replaceSubrange(20..<24, with: [0, 0, 0x4e, 0x20])
    var crc: UInt32 = 0xffff_ffff
    for byte in bytes[12..<29] {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xedb8_8320 : crc >> 1 }
    }
    crc ^= 0xffff_ffff
    bytes.replaceSubrange(29..<33, with: [UInt8(crc >> 24), UInt8((crc >> 16) & 255), UInt8((crc >> 8) & 255), UInt8(crc & 255)])
    try bytes.write(to: url)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    #expect(throws: ImageLibraryError.self) { try ImageDecoding.dimensions(source) }
    let library = try AssetLibrary(rootURL: root.appendingPathComponent("library"))
    #expect(try library.importImages([url]).isEmpty)
}

@Test func testDefaultCacheNeverKeepsMoreThanEight() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let url = try fixture(root)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let cache = BackgroundCache(maximumCount: 99)
    for index in 0..<9 { cache.insert(image, forKey: "\(index)") }
    #expect(cache.image(forKey: "0") == nil)
    for index in 1..<9 { #expect(cache.image(forKey: "\(index)") != nil) }
}

@Test func testMissingPhotoRendersOpaqueDefault() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let image = try Compositor.render(selection: Selection(layoutMode: .hero, assets: []), size: CGSize(width: 80, height: 60), libraryURL: root)
    let data = try pixels(image)
    #expect(stride(from: 3, to: data.count, by: 4).allSatisfy { data[$0] == 255 })
    #expect(throws: ImageLibraryError.self) {
        try Compositor.render(selection: Selection(layoutMode: .hero, assets: []), size: .zero, libraryURL: root)
    }
}

@Test func testSourcePixelBudgetRejectsLargeJPEGHeader() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let url = try fixture(root, name: "huge.jpg", type: "public.jpeg" as CFString)
    var bytes = try Data(contentsOf: url)
    let marker = try #require((0..<(bytes.count - 10)).first { bytes[$0] == 0xff && (bytes[$0 + 1] == 0xc0 || bytes[$0 + 1] == 0xc2) })
    bytes.replaceSubrange((marker + 5)..<(marker + 9), with: [0x4e, 0x20, 0x4e, 0x20])
    try bytes.write(to: url)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    #expect(throws: ImageLibraryError.self) { try ImageDecoding.dimensions(source) }
}

@Test func testPixelBudgetValidation() {
    #expect(throws: ImageLibraryError.self) { try ImageDecoding.validateDimensions(width: 20000, height: 20000) }
    #expect(throws: ImageLibraryError.self) { try ImageDecoding.validateDimensions(width: 0, height: 100) }
    #expect(throws: ImageLibraryError.self) { try ImageDecoding.validateDimensions(width: .nan, height: 100) }
}

@Test func testCacheEnforces128MiBCeiling() throws {
    let context = try #require(CGContext(data: nil, width: 4096, height: 4096, bitsPerComponent: 8,
        bytesPerRow: 4096 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    let cache = BackgroundCache(maximumBytes: Int.max)
    for key in ["a", "b", "c"] { cache.insert(image, forKey: key) }
    #expect(cache.image(forKey: "a") == nil)
    #expect(cache.image(forKey: "b") != nil && cache.image(forKey: "c") != nil)
}
