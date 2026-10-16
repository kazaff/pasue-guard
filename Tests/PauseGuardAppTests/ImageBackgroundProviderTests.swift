import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import PauseGuardImages
import PauseGuardPlatform
@testable import PauseGuardApp

@Suite @MainActor struct ImageBackgroundProviderTests {
    @Test func requestWithoutPreparationImmediatelyUsesDefaultAndCompletesWithoutIO() async {
        let provider = ImageBackgroundProvider(libraryURL: URL(fileURLWithPath: "/unreadable/pauseguard-images"))
        let screen = DisplayDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1, isMain: true)
        var called = false
        let initial = provider.image(for: screen) { image in #expect(image == nil); called = true }
        #expect(initial == nil)
        #expect(called)
    }
    @Test func preparationRendersActualPixelsPerScreenAndInvalidatesAfterMutation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = try #require(CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 80,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.3, blue: 0.1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        let source = root.appendingPathComponent("source.png")
        let destination = try #require(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        let provider = ImageBackgroundProvider(libraryURL: root.appendingPathComponent("library"))
        let assets = try await provider.importImages([source])
        #expect(assets.count == 1)
        let screen = DisplayDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 120, height: 60), scale: 2, isMain: true)
        provider.prepare(for: [screen])
        let rendered: CGImage? = await withCheckedContinuation { continuation in
            let cached = provider.image(for: screen) { continuation.resume(returning: $0) }
            if let cached { continuation.resume(returning: cached) }
        }
        #expect(rendered?.width == 240)
        #expect(rendered?.height == 120)
        #expect(provider.image(for: screen, completion: { _ in }) != nil)
        try await provider.removeImage(id: assets[0].id)
        #expect(provider.image(for: screen, completion: { _ in }) == nil)
        #expect(try await provider.librarySnapshot().assets.isEmpty)
    }
    @Test func invalidationDropsPreparedCacheAndMissingLibrarySafelyFallsBack() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = ImageBackgroundProvider(libraryURL: root)
        let screen = DisplayDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 50), scale: 1, isMain: true)
        provider.prepare(for: [screen])
        let image = await withCheckedContinuation { continuation in
            _ = provider.image(for: screen) { continuation.resume(returning: $0) }
        }
        #expect(image == nil)
        provider.invalidate()
        #expect(provider.image(for: screen, completion: { _ in }) == nil)
    }
}
