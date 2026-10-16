import Foundation
public struct ImageAsset: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let fileName: String
    public let width: Int
    public let height: Int
    public let thumbnailName: String
    public init(id: UUID = UUID(), fileName: String, width: Int, height: Int, thumbnailName: String) {
        self.id = id; self.fileName = fileName; self.width = width; self.height = height; self.thumbnailName = thumbnailName
    }
}
public enum LayoutMode: String, Codable, Sendable, CaseIterable { case hero, grid, collage, cinematic, minimal, random
    public static var concreteCases: [LayoutMode] { [.hero, .grid, .collage, .cinematic, .minimal] }
}
public struct BreakTheme: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var imageIDs: [UUID]
    public var layoutMode: LayoutMode
    public init(id: UUID = UUID(), name: String, enabled: Bool = true, imageIDs: [UUID] = [], layoutMode: LayoutMode = .hero) {
        self.id = id; self.name = name; self.enabled = enabled; self.imageIDs = imageIDs; self.layoutMode = layoutMode
    }
}
