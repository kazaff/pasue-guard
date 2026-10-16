import Foundation
import CoreGraphics

public enum ThemePreviewError: Error, Equatable { case emptySelection, unavailableImages }

public struct TemplatePreview: Sendable {
    public let layout: LayoutMode
    public let selection: Selection
    public let image: CGImage
}

/// Read-only, serial, bounded draft rendering. Intentionally owns no AssetLibrary,
/// selector history, background cache, or reference to the timer/provider.
public actor ThemePreviewRenderer {
    private let libraryURL: URL
    public init(libraryURL: URL) { self.libraryURL = libraryURL }

    public func render(theme: BreakTheme, assets: [ImageAsset], singleImage: Bool,
                       aspectRatio: Double) throws -> [TemplatePreview] {
        try Task.checkCancellation()
        guard !theme.imageIDs.isEmpty else { throw ThemePreviewError.emptySelection }
        let byID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var selected: [ImageAsset] = []
        // Decode only enough usable draft photos for the compositor's four tiles.
        for id in theme.imageIDs {
            try Task.checkCancellation()
            guard let asset = byID[id], !selected.contains(where: { $0.id == id }),
                  (try? ImageDecoding.load(asset, libraryURL: libraryURL, maxPixel: 640)) != nil else { continue }
            selected.append(asset)
            if selected.count == (singleImage ? 1 : 4) { break }
        }
        guard !selected.isEmpty else { throw ThemePreviewError.unavailableImages }
        let ratio = aspectRatio.isFinite && aspectRatio > 0 ? max(0.2, min(5, aspectRatio)) : 16.0 / 9
        let size = ratio >= 1 ? CGSize(width: 640, height: max(1, (640 / ratio).rounded()))
            : CGSize(width: max(1, (640 * ratio).rounded()), height: 640)
        var previews: [TemplatePreview] = []
        for layout in LayoutMode.concreteCases {
            try Task.checkCancellation()
            let selection = Selection(themeID: theme.id, layoutMode: layout, assets: selected)
            let image = try Compositor.render(selection: selection, size: size, libraryURL: libraryURL)
            try Task.checkCancellation()
            previews.append(TemplatePreview(layout: layout, selection: selection, image: image))
        }
        return previews
    }
}
