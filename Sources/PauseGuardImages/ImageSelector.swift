import Foundation
public struct Selection: Sendable, Equatable {
    public var themeID: UUID?
    public var layoutMode: LayoutMode
    public var assets: [ImageAsset]
    public init(themeID: UUID? = nil, layoutMode: LayoutMode, assets: [ImageAsset]) {
        self.themeID = themeID; self.layoutMode = layoutMode; self.assets = assets
    }
}
public enum ImageSelector {
    /// Nil requests the built-in non-photo background; disabled themes never leak photos.
    public static func select(themes: [BreakTheme], assets: [ImageAsset], previous: Selection?) -> Selection? {
        let available = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var choices: [(BreakTheme, ImageAsset)] = []
        for theme in themes where theme.enabled {
            var seen = Set<UUID>()
            for id in theme.imageIDs where seen.insert(id).inserted {
                if let asset = available[id] { choices.append((theme, asset)) }
            }
        }
        if let previousID = previous?.assets.first?.id {
            let alternatives = choices.filter { $0.1.id != previousID }
            if !alternatives.isEmpty { choices = alternatives }
        }
        if let previousTheme = previous?.themeID {
            let alternatives = choices.filter { $0.0.id != previousTheme }
            if !alternatives.isEmpty { choices = alternatives }
        }
        guard let (theme, first) = choices.randomElement() else { return nil }
        var seen: Set<UUID> = [first.id]
        let rest = theme.imageIDs.compactMap { available[$0] }.filter { seen.insert($0.id).inserted }.shuffled()
        let mode: LayoutMode
        if theme.layoutMode == .random {
            let layouts = LayoutMode.concreteCases.filter { $0 != previous?.layoutMode }
            mode = layouts.randomElement() ?? .hero
        } else { mode = theme.layoutMode }
        return Selection(themeID: theme.id, layoutMode: mode, assets: [first] + rest.prefix(3))
    }
}
