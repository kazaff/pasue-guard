import Foundation
import ImageIO

internal enum ImageDecoding {
    static func isLocalName(_ name: String) -> Bool { !name.isEmpty && name == (name as NSString).lastPathComponent && name != "." && name != ".." }
    static func validateDimensions(width: Double, height: Double) throws {
        // Even codecs that cannot truly downsample internally have a finite source budget.
        guard width.isFinite, height.isFinite, width >= 1, height >= 1,
              width <= 32768, height <= 32768, width * height <= 64_000_000 else { throw ImageLibraryError.invalidSize }
    }
    static func dimensions(_ source: CGImageSource) throws -> (Int, Int) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite else { throw ImageLibraryError.invalidSize }
        try validateDimensions(width: width, height: height)
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? (Int(height), Int(width)) : (Int(width), Int(height))
    }
    static func thumbnail(_ source: CGImageSource, maxPixel: Int) throws -> CGImage {
        _ = try dimensions(source)
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, min(4096, maxPixel)),
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { throw ImageLibraryError.invalidImage }
        return image
    }
    static func load(_ asset: ImageAsset, libraryURL: URL, maxPixel: Int) throws -> CGImage {
        guard isLocalName(asset.fileName),
              let source = CGImageSourceCreateWithURL(libraryURL.appendingPathComponent(asset.fileName) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw ImageLibraryError.invalidImage }
        return try thumbnail(source, maxPixel: maxPixel)
    }
}
