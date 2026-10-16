import Foundation
import CoreGraphics
import PauseGuardImages
import PauseGuardPlatform

public struct ImageLibrarySnapshot: Sendable {
    public let assets: [ImageAsset]
    public let themes: [BreakTheme]
}

/// One serial actor owns the non-Sendable AssetLibrary. Selection is shared by
/// all displays; compositing and disk I/O never execute on the main actor.
private func backgroundKey(revision: UUID, display: DisplayDescriptor) -> String {
    "\(revision):\(display.pixelSize.width)x\(display.pixelSize.height)"
}

private actor ImageBackgroundWorker {
    let root: URL
    var library: AssetLibrary?
    var previous: Selection?
    let cache: BackgroundCache
    init(root: URL, cache: BackgroundCache) { self.root = root; self.cache = cache }
    func load() throws -> AssetLibrary {
        if let library { return library }
        let result = try AssetLibrary(rootURL: root); library = result; return result
    }
    func select(singleImage: Bool) -> Selection? {
        guard let library = try? load() else { return nil }
        guard let next = ImageSelector.select(themes: library.themes, assets: library.assets, previous: previous) else { return nil }
        let selected = singleImage ? Selection(themeID: next.themeID, layoutMode: next.layoutMode, assets: Array(next.assets.prefix(1))) : next
        previous = selected
        return selected
    }
    func render(selection: Selection, display: DisplayDescriptor, revision: UUID) -> CGImage? {
        let size = display.pixelSize
        let key = backgroundKey(revision: revision, display: display)
        if let image = cache.image(forKey: key) { return image }
        guard let image = try? Compositor.render(selection: selection, size: size, libraryURL: root) else { return nil }
        cache.insert(image, forKey: key)
        return image
    }
    func invalidate() { cache.removeAll() }
    func snapshot() throws -> ImageLibrarySnapshot {
        let library = try load()
        return ImageLibrarySnapshot(assets: library.assets, themes: library.themes)
    }
    func importImages(_ urls: [URL]) throws -> [ImageAsset] { try load().importImages(urls) }
    func removeImage(id: UUID) throws { try load().removeImage(id: id) }
    func saveThemes(_ themes: [BreakTheme]) throws { try load().saveThemes(themes) }
}

@MainActor public final class ImageBackgroundProvider: BackgroundProvider {
    private let worker: ImageBackgroundWorker
    private var revision = UUID()
    private var selectionTask: Task<Selection?, Never>?
    private let cache = BackgroundCache()
    private var preparation: Task<Void, Never>?
    public init(libraryURL: URL) { worker = ImageBackgroundWorker(root: libraryURL, cache: cache) }

    /// Call once per upcoming break while working, including after library edits.
    /// Preparation chooses one common theme/layout for all requested displays.
    public func prepare(for displays: [DisplayDescriptor], singleImage: Bool = false) {
        invalidate()
        let token = revision, worker = worker
        let task = Task { await worker.select(singleImage: singleImage) }
        selectionTask = task
        preparation = Task { [weak self] in
            guard let selection = await task.value else { return }
            for display in displays {
                guard !Task.isCancelled else { return }
                guard let self, self.revision == token else { return }
                _ = await worker.render(selection: selection, display: display, revision: token)
            }
        }
    }
    public func invalidate() {
        revision = UUID(); selectionTask?.cancel(); selectionTask = nil
        preparation?.cancel(); preparation = nil; cache.removeAll()
        let worker = worker
        Task { await worker.invalidate() }
    }
    public func image(for display: DisplayDescriptor, completion: @escaping @MainActor (CGImage?) -> Void) -> CGImage? {
        if let cached = cache.image(forKey: backgroundKey(revision: revision, display: display)) { return cached }
        guard let selectionTask else { completion(nil); return nil }
        let token = revision, worker = worker
        Task { [weak self] in
            guard let selection = await selectionTask.value else { completion(nil); return }
            let image = await worker.render(selection: selection, display: display, revision: token)
            guard let self, self.revision == token else { completion(nil); return }
            completion(image)
        }
        return nil
    }
    /// Use these entry points instead of sharing AssetLibrary across actors.
    public func librarySnapshot() async throws -> ImageLibrarySnapshot { try await worker.snapshot() }
    @discardableResult public func importImages(_ urls: [URL]) async throws -> [ImageAsset] {
        invalidate(); return try await worker.importImages(urls)
    }
    public func removeImage(id: UUID) async throws { invalidate(); try await worker.removeImage(id: id) }
    public func saveThemes(_ themes: [BreakTheme]) async throws { invalidate(); try await worker.saveThemes(themes) }
}
