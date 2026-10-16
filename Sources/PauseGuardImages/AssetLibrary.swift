import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

public enum ImageLibraryError: Error { case unsupportedMetadataVersion, invalidImage, invalidSize, cannotCreateImage }

/// Synchronous disk API. Own one instance on one serial executor; do not call concurrently.
/// Imported original bytes are preserved, with EXIF orientation applied only when decoding.
public final class AssetLibrary {
    public let rootURL: URL
    public private(set) var assets: [ImageAsset] = []
    public private(set) var themes: [BreakTheme] = []
    private var hashes: [UUID: String] = [:]
    private static let defaultThemeID = UUID(uuidString: "A98244DD-C312-4EC4-AB5B-95EE06E53601")!
    private struct Metadata: Codable {
        var version = 1
        var assets: [ImageAsset]
        var themes: [BreakTheme]
        var hashes: [UUID: String]
    }
    public init(rootURL: URL) throws {
        self.rootURL = rootURL
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let metadataURL = rootURL.appendingPathComponent("library.json")
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            let stored = try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metadataURL))
            guard stored.version == 1 else { throw ImageLibraryError.unsupportedMetadataVersion }
            assets = stored.assets.filter { ImageDecoding.isLocalName($0.fileName) && ImageDecoding.isLocalName($0.thumbnailName) && $0.width > 0 && $0.height > 0 }
            hashes = stored.hashes
            themes = normalized(stored.themes)
        }
    }
    /// Invalid, oversized, unsupported, or unreadable items are skipped independently.
    /// Metadata/storage errors throw; successful earlier items in the batch are persisted.
    @discardableResult public func importImages(_ urls: [URL]) throws -> [ImageAsset] {
        var result: [ImageAsset] = []
        var seen = Set<UUID>()
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let prepared = try? prepare(url) else { continue }
            if let existing = assets.first(where: { hashes[$0.id] == prepared.hash }) {
                if seen.insert(existing.id).inserted { result.append(existing) }
                continue
            }
            let id = UUID()
            let fileName = id.uuidString + "." + prepared.extensionName
            let thumb = id.uuidString + "-thumb.png"
            let originalURL = rootURL.appendingPathComponent(fileName)
            let thumbURL = rootURL.appendingPathComponent(thumb)
            do {
                try FileManager.default.copyItem(at: url, to: originalURL)
                guard let destination = CGImageDestinationCreateWithURL(thumbURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw ImageLibraryError.cannotCreateImage }
                CGImageDestinationAddImage(destination, prepared.thumbnail, nil)
                guard CGImageDestinationFinalize(destination) else { throw ImageLibraryError.cannotCreateImage }
                let asset = ImageAsset(id: id, fileName: fileName, width: prepared.width, height: prepared.height, thumbnailName: thumb)
                let oldThemes = themes
                assets.append(asset); hashes[id] = prepared.hash
                if let index = themes.firstIndex(where: { $0.id == Self.defaultThemeID }) { themes[index].imageIDs.append(id) }
                else if themes.isEmpty { themes = [BreakTheme(id: Self.defaultThemeID, name: "Default", imageIDs: [id])] }
                do { try persist() }
                catch { assets.removeAll { $0.id == id }; hashes[id] = nil; themes = oldThemes; throw error }
                seen.insert(id); result.append(asset)
            } catch {
                try? FileManager.default.removeItem(at: originalURL)
                try? FileManager.default.removeItem(at: thumbURL)
                throw error
            }
        }
        return result
    }
    public func removeImage(id: UUID) throws {
        guard let asset = assets.first(where: { $0.id == id }) else { return }
        let oldAssets = assets, oldThemes = themes, oldHashes = hashes
        assets.removeAll { $0.id == id }; hashes[id] = nil
        themes = normalized(themes)
        do { try persist() } catch { assets = oldAssets; themes = oldThemes; hashes = oldHashes; throw error }
        // Persist references first: an interrupted delete can leave an unreferenced file, never a dangling theme.
        for name in [asset.fileName, asset.thumbnailName] {
            let url = rootURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
    public func saveThemes(_ themes: [BreakTheme]) throws {
        let old = self.themes
        self.themes = normalized(themes)
        do { try persist() } catch { self.themes = old; throw error }
    }
    private func normalized(_ input: [BreakTheme]) -> [BreakTheme] {
        let valid = Set(assets.map(\.id)); var themeIDs = Set<UUID>()
        return input.filter { themeIDs.insert($0.id).inserted }.map { theme in
            var theme = theme; var seen = Set<UUID>()
            theme.imageIDs = theme.imageIDs.filter { valid.contains($0) && seen.insert($0).inserted }
            return theme
        }
    }
    private func persist() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Metadata(assets: assets, themes: themes, hashes: hashes)).write(to: rootURL.appendingPathComponent("library.json"), options: .atomic)
    }
    private func prepare(_ url: URL) throws -> (hash: String, extensionName: String, width: Int, height: Int, thumbnail: CGImage) {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 100 * 1024 * 1024,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.heif.identifier].contains(type)
        else { throw ImageLibraryError.invalidImage }
        let dimensions = try ImageDecoding.dimensions(source)
        let thumb = try ImageDecoding.thumbnail(source, maxPixel: 512)
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hasher = SHA256()
        while let block = try handle.read(upToCount: 1024 * 1024), !block.isEmpty { hasher.update(data: block) }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (digest, type == UTType.png.identifier ? "png" : type == UTType.jpeg.identifier ? "jpg" : "heic", dimensions.0, dimensions.1, thumb)
    }
}
