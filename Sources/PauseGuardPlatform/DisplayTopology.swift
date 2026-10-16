import AppKit

public struct DisplayDescriptor: Equatable, Sendable, Identifiable {
    public let id: UInt32
    public let frame: CGRect
    public let scale: CGFloat
    public let isMain: Bool
    public init(id: UInt32, frame: CGRect, scale: CGFloat, isMain: Bool) {
        self.id = id; self.frame = frame; self.scale = scale; self.isMain = isMain
    }
    public var pixelSize: CGSize { CGSize(width: frame.width * scale, height: frame.height * scale) }
}

public struct DisplayChanges: Sendable {
    public let added: [DisplayDescriptor]
    public let removed: [DisplayDescriptor]
    public let updated: [DisplayDescriptor]
}

public enum DisplayTopology {
    public static func diff(previous: [DisplayDescriptor], current: [DisplayDescriptor]) -> DisplayChanges {
        let old = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let new = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return DisplayChanges(added: current.filter { old[$0.id] == nil },
                              removed: previous.filter { new[$0.id] == nil },
                              updated: current.filter { old[$0.id] != nil && old[$0.id] != $0 })
    }
    @MainActor public static func current() -> [DisplayDescriptor] {
        let screens = NSScreen.screens
        return screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return DisplayDescriptor(id: id.uint32Value, frame: screen.frame,
                                     scale: screen.backingScaleFactor, isMain: screen == screens.first)
        }
    }
}
