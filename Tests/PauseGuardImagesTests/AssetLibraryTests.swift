import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PauseGuardImages

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
func fixture(_ root: URL, name: String = "source.png", width: Int = 120, height: Int = 80,
             type: CFString = UTType.png.identifier as CFString, orientation: Int = 1,
             color: CGColor = CGColor(red: 1, green: 0.3, blue: 0.1, alpha: 1)) throws -> URL {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(color); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width / 3, height: height / 2))
    let url = root.appendingPathComponent(name)
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), [kCGImagePropertyOrientation: orientation] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

@Test func testImportCopiesSource() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let source = try fixture(root)
    let library = try AssetLibrary(rootURL: root.appendingPathComponent("library"))
    let assets = try library.importImages([source])
    let asset = try #require(assets.first)
    #expect(asset.width == 120 && asset.height == 80)
    #expect(try Data(contentsOf: source) == Data(contentsOf: library.rootURL.appendingPathComponent(asset.fileName)))
    try FileManager.default.removeItem(at: source)
    #expect(FileManager.default.fileExists(atPath: library.rootURL.appendingPathComponent(asset.thumbnailName).path))
    #expect(try AssetLibrary(rootURL: library.rootURL).assets == assets)
}

@Test func testCorruptFileSkipped() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let broken = root.appendingPathComponent("broken.png"); try Data("no image".utf8).write(to: broken)
    let source = try fixture(root)
    let library = try AssetLibrary(rootURL: root.appendingPathComponent("library"))
    #expect(try library.importImages([broken, source]).count == 1)
}

@Test func testDeleteUpdatesThemes() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let library = try AssetLibrary(rootURL: root.appendingPathComponent("library"))
    let asset = try #require(library.importImages([fixture(root)]).first)
    try library.saveThemes([BreakTheme(name: "Nature", imageIDs: [asset.id, asset.id])])
    #expect(library.themes.first?.imageIDs == [asset.id])
    try library.removeImage(id: asset.id)
    #expect(library.themes.first?.imageIDs.isEmpty == true)
    #expect(library.assets.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: library.rootURL.appendingPathComponent(asset.fileName).path))
    #expect(try AssetLibrary(rootURL: library.rootURL).themes.first?.imageIDs.isEmpty == true)
}

@Test func testJPEGOrientationAndDuplicateImports() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let url = try fixture(root, name: "source.jpg", type: UTType.jpeg.identifier as CFString, orientation: 6)
    let library = try AssetLibrary(rootURL: root.appendingPathComponent("library"))
    let imported = try library.importImages([url, url])
    #expect(imported.count == 1)
    #expect(imported.first?.width == 80 && imported.first?.height == 120)
    #expect(try library.importImages([url]).first?.id == imported.first?.id)
    #expect(library.assets.count == 1)
    let asset = try #require(imported.first)
    let thumbnailSource = try #require(CGImageSourceCreateWithURL(library.rootURL.appendingPathComponent(asset.thumbnailName) as CFURL, nil))
    let thumbnail = try #require(CGImageSourceCreateImageAtIndex(thumbnailSource, 0, nil))
    #expect(thumbnail.width == 80 && thumbnail.height == 120)
}

@Test func testRejectsOversizedImportAndContinues() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let huge = try fixture(root, name: "huge.png")
    let handle = try FileHandle(forWritingTo: huge)
    try handle.truncate(atOffset: 100 * 1024 * 1024 + 1); try handle.close()
    let good = try fixture(root, name: "good.png")
    let library = try AssetLibrary(rootURL: root.appendingPathComponent("library"))
    #expect(try library.importImages([huge, good]).count == 1)
    #expect(library.themes.first?.enabled == true)
    #expect(library.themes.first?.imageIDs == library.assets.map(\.id))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAUSEGUARD_TEST_HEIC_ENCODER"] == "1", "Requires a working local HEIC encoder; opt in with PAUSEGUARD_TEST_HEIC_ENCODER=1"))
func testHEICImportWhenEncoderAvailable() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let source = try fixture(root)
    let input = try #require(CGImageSourceCreateWithURL(source as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(input, 0, nil))
    let url = root.appendingPathComponent("source.heic")
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 8] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { print("HEIC encoder unavailable in this environment; optional encoding test skipped"); return }
    let library = try AssetLibrary(rootURL: root.appendingPathComponent("library"))
    let asset = try #require(library.importImages([url]).first)
    #expect(asset.width == 80 && asset.height == 120)
    let thumbnail = try #require(CGImageSourceCreateWithURL(library.rootURL.appendingPathComponent(asset.thumbnailName) as CFURL, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(thumbnail, 0, nil))
    #expect(decoded.width == 80 && decoded.height == 120)
}

@Test(arguments: [Data("broken metadata".utf8), Data(#"{"version":999,"assets":[],"themes":[],"hashes":[]}"#.utf8)])
func testDamagedMetadataRecoversOnlyOnExplicitMutation(bytes: Data) throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let source = try fixture(root)
    let directory = root.appendingPathComponent("library")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let metadata = directory.appendingPathComponent("library.json")
    try bytes.write(to: metadata)
    let original = directory.appendingPathComponent("old-original.png")
    let thumbnail = directory.appendingPathComponent("old-thumb.png")
    try Data("original".utf8).write(to: original)
    try Data("thumbnail".utf8).write(to: thumbnail)
    let library = try AssetLibrary(rootURL: directory)
    #expect(library.assets.isEmpty && library.themes.isEmpty)
    #expect(try Data(contentsOf: metadata) == bytes)
    #expect(try library.importImages([root.appendingPathComponent("missing.png")]).isEmpty)
    #expect(try Data(contentsOf: metadata) == bytes)
    let imported = try #require(library.importImages([source]).first)
    try library.saveThemes([BreakTheme(name: "Recovered", imageIDs: [imported.id])])
    let reloaded = try AssetLibrary(rootURL: directory)
    #expect(reloaded.assets == [imported])
    #expect(reloaded.themes.first?.name == "Recovered")
    #expect(reloaded.themes.first?.imageIDs == [imported.id])
    let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("library.json.preserved-") }
    #expect(backups.count == 1)
    #expect(try Data(contentsOf: #require(backups.first)) == bytes)
    #expect(try Data(contentsOf: original) == Data("original".utf8))
    #expect(try Data(contentsOf: thumbnail) == Data("thumbnail".utf8))
}

@Test func testLibraryFilesystemFailuresRemainErrors() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("library")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let metadata = directory.appendingPathComponent("library.json")
    try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
    #expect(throws: (any Error).self) { try AssetLibrary(rootURL: directory) }
    try FileManager.default.removeItem(at: metadata)
    let library = try AssetLibrary(rootURL: directory)
    try FileManager.default.removeItem(at: directory)
    try Data("storage is a file".utf8).write(to: directory)
    #expect(throws: (any Error).self) { try library.saveThemes([BreakTheme(name: "No write", imageIDs: [])]) }
    #expect(library.themes.isEmpty)
}

@Test func testThemeFirstRecoveryPreservesMetadataBeforeWriting() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let metadata = root.appendingPathComponent("library.json")
    let damaged = Data("damaged".utf8)
    try damaged.write(to: metadata)
    let library = try AssetLibrary(rootURL: root)
    try library.saveThemes([BreakTheme(name: "Fresh theme", imageIDs: [])])
    #expect(try AssetLibrary(rootURL: root).themes.first?.name == "Fresh theme")
    let backup = try #require(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("library.json.preserved-") })
    #expect(try Data(contentsOf: backup) == damaged)
    let second = Data("damaged again".utf8)
    try second.write(to: metadata)
    try AssetLibrary(rootURL: root).saveThemes([BreakTheme(name: "Second recovery", imageIDs: [])])
    let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("library.json.preserved-") }
    #expect(backups.count == 2)
    #expect(try backups.map { try Data(contentsOf: $0) }.contains(second))
    #expect(try Data(contentsOf: backup) == damaged)
}

@Test func testUnwritableCorruptMetadataCannotBeSilentlyReplaced() throws {
    let root = try temporaryDirectory(); defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }
    let metadata = root.appendingPathComponent("library.json")
    let bytes = Data("broken".utf8)
    try bytes.write(to: metadata)
    let library = try AssetLibrary(rootURL: root)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
    #expect(throws: (any Error).self) { try library.saveThemes([BreakTheme(name: "Denied", imageIDs: [])]) }
    #expect(try Data(contentsOf: metadata) == bytes)
    #expect(library.themes.isEmpty)
}

@Test func testUnreadableMetadataDoesNotBecomeAnEmptyLibrary() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let metadata = root.appendingPathComponent("library.json")
    try Data("broken".utf8).write(to: metadata)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: metadata.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadata.path) }
    #expect(throws: (any Error).self) { try AssetLibrary(rootURL: root) }
}

@Test func testInaccessibleLibraryDirectoryCannotMasqueradeAsMissingMetadata() throws {
    let root = try temporaryDirectory(); defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }
    try Data("broken".utf8).write(to: root.appendingPathComponent("library.json"))
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: root.path)
    #expect(throws: (any Error).self) { try AssetLibrary(rootURL: root) }
}
