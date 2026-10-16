import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import PauseGuardImages
import PauseGuardPlatform
@testable import PauseGuardApp

@Suite @MainActor struct ThemePreviewTests {
    private func fixture(_ root: URL, name: String, color: CGColor) throws -> URL {
        let context = try #require(CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 160,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(color); context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let url = root.appendingPathComponent(name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination)); return url
    }
    private func contents(_ root: URL) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }
    // Catches using a fixed virtual width: doubling logical display points must
    // halve the panel/photo ratio when both complete scenes are fitted to a card.
    @Test func previewPanelScaleMatchesLogicalDisplaySize() throws {
        let context = try #require(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 160,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let source = try #require(context.makeImage())
        func panelWidth(displaySize: CGSize) throws -> Int {
            let scene = BreakPreviewScene(image: source, displaySize: displaySize,
                reduceVisualStimulation: false)
                .frame(width: 640, height: 320)
            let image = try #require(ImageRenderer(content: scene).cgImage)
            var bytes = [UInt8](repeating: 0, count: 640 * 320 * 4)
            bytes.withUnsafeMutableBytes { buffer in
                let output = CGContext(data: buffer.baseAddress, width: 640, height: 320, bitsPerComponent: 8, bytesPerRow: 2560,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                output.draw(image, in: CGRect(x: 0, y: 0, width: 640, height: 320))
            }
            // The local frost dims green. Measure its extent independently of
            // hue/gray material, so transparent glass preserves this scale oracle.
            let occupied = (0..<640).filter { bytes[(160 * 640 + $0) * 4 + 1] < 225 }
            return try #require(occupied.last) - #require(occupied.first) + 1
        }
        let small = try panelWidth(displaySize: CGSize(width: 1280, height: 640))
        let large = try panelWidth(displaySize: CGSize(width: 2560, height: 1280))
        #expect(small > 100)
        #expect(Double(large) / Double(small) > 0.4)
        #expect(Double(large) / Double(small) < 0.6)
    }
    @Test func galleryFitsSmallVisibleDesktopAndKeepsLogicalSceneDimensions() {
        let display = PreviewDisplayGeometry(screenSize: CGSize(width: 2560, height: 1440), visibleSize: CGSize(width: 800, height: 600))
        #expect(display.sceneSize == CGSize(width: 2560, height: 1440))
        #expect(display.gallerySize.width <= 800 && display.gallerySize.height <= 600)
        #expect(display.gallerySize.width > 600 && display.gallerySize.height > 400)
        let other = PreviewDisplayGeometry(screenSize: CGSize(width: 1280, height: 720), visibleSize: CGSize(width: 800, height: 600))
        #expect(display != other, "Same aspect ratio still needs distinct logical display geometry")
        let fallback = PreviewDisplayGeometry(screenSize: nil, visibleSize: nil)
        #expect(fallback.sceneSize.width / fallback.sceneSize.height == 16.0 / 9)
        #expect(fallback.gallerySize.width <= 800 && fallback.gallerySize.height <= 600)
    }
    // Catches previews accidentally reading saved themes, choosing unrelated photos, or changing the prepared break.
    @Test func draftGalleryUsesOnlyDraftPhotosAndLeavesLibraryAndPreparedBreakUntouched() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let libraryURL = root.appendingPathComponent("library")
        let provider = ImageBackgroundProvider(libraryURL: libraryURL)
        let assets = try await provider.importImages([
            fixture(root, name: "red.png", color: CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
            fixture(root, name: "green.png", color: CGColor(red: 0, green: 1, blue: 0, alpha: 1))])
        let saved = BreakTheme(name: "saved", imageIDs: [assets[0].id])
        try await provider.saveThemes([saved])
        let display = DisplayDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 120, height: 60), scale: 1, isMain: true)
        provider.prepare(for: [display])
        let beforeImage: CGImage? = await withCheckedContinuation { continuation in
            if let cached = provider.image(for: display, completion: { continuation.resume(returning: $0) }) { continuation.resume(returning: cached) }
        }
        let before = try contents(libraryURL)
        let renderer = ThemePreviewRenderer(libraryURL: libraryURL)
        let draft = BreakTheme(name: "unsaved", enabled: false, imageIDs: [assets[1].id], layoutMode: .random)
        let gallery = try await renderer.render(theme: draft, assets: assets, singleImage: false, aspectRatio: 2)
        #expect(gallery.map(\.layout) == [.hero, .grid, .collage, .cinematic, .minimal])
        for preview in gallery {
            #expect(preview.selection.assets.map(\.id) == [assets[1].id])
            #expect(preview.image.width == 640 && preview.image.height == 320)
        }
        if let folder = ProcessInfo.processInfo.environment["PAUSEGUARD_PREVIEW_DIR"] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            for preview in gallery {
                let scene = BreakPreviewScene(image: preview.image, displaySize: CGSize(width: 2560, height: 1280), reduceVisualStimulation: false)
                    .frame(width: 960, height: 480)
                let image = try #require(ImageRenderer(content: scene).cgImage)
                let url = URL(fileURLWithPath: folder).appendingPathComponent("panel-\(preview.layout.rawValue).png")
                let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(destination, image, nil); #expect(CGImageDestinationFinalize(destination))
            }
        }
        #expect(try contents(libraryURL) == before)
        #expect(try await provider.librarySnapshot().themes == [saved])
        #expect(provider.image(for: display, completion: { _ in }) === beforeImage)
    }
    @Test func missingLibraryIsReadOnlyAndReportsUnavailablePhotos() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let asset = ImageAsset(fileName: "deleted.png", width: 40, height: 30, thumbnailName: "deleted-thumb.png")
        let renderer = ThemePreviewRenderer(libraryURL: root)
        await #expect(throws: ThemePreviewError.unavailableImages) {
            try await renderer.render(theme: BreakTheme(name: "draft", imageIDs: [asset.id]), assets: [asset], singleImage: false, aspectRatio: 1)
        }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
    // Catches ignoring draft order/single-photo preference, and silently displaying dark cards for deleted files.
    @Test func singleModeMissingPhotosAndCancellation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try AssetLibrary(rootURL: root.appendingPathComponent("library"))
        let assets = try library.importImages([
            fixture(root, name: "red.png", color: CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
            fixture(root, name: "green.png", color: CGColor(red: 0, green: 1, blue: 0, alpha: 1))])
        let renderer = ThemePreviewRenderer(libraryURL: library.rootURL)
        let draft = BreakTheme(name: "draft", imageIDs: [assets[1].id, assets[0].id])
        let single = try await renderer.render(theme: draft, assets: assets, singleImage: true, aspectRatio: .nan)
        #expect(single.allSatisfy { $0.selection.assets.map(\.id) == [assets[1].id] && $0.image.width == 640 && $0.image.height == 360 })
        let multiple = try await renderer.render(theme: draft, assets: assets, singleImage: false, aspectRatio: 1)
        #expect(multiple.allSatisfy { $0.selection.assets.map(\.id) == [assets[1].id, assets[0].id] })
        try FileManager.default.removeItem(at: library.rootURL.appendingPathComponent(assets[1].fileName))
        let partial = try await renderer.render(theme: draft, assets: assets, singleImage: true, aspectRatio: 1)
        #expect(partial.allSatisfy { $0.selection.assets.map(\.id) == [assets[0].id] })
        await #expect(throws: ThemePreviewError.emptySelection) { try await renderer.render(theme: BreakTheme(name: "empty", imageIDs: []), assets: assets, singleImage: false, aspectRatio: 1) }
        await #expect(throws: ThemePreviewError.unavailableImages) { try await renderer.render(theme: BreakTheme(name: "missing", imageIDs: [assets[1].id, UUID()]), assets: assets, singleImage: false, aspectRatio: 1) }
        let task = Task { try await renderer.render(theme: draft, assets: assets, singleImage: false, aspectRatio: 1) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
