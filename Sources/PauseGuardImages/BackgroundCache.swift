import Foundation
import CoreGraphics

/// Thread-safe LRU of immutable, already-rendered backgrounds. Keys must include selection,
/// target pixel size, and any library revision. Entries larger than the byte budget are not retained.
public final class BackgroundCache: @unchecked Sendable {
    private struct Entry { let image: CGImage; let bytes: Int }
    private let lock = NSLock()
    private let maximumCount: Int
    private let maximumBytes: Int
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var bytes = 0
    public init(maximumCount: Int = 8, maximumBytes: Int = 128 * 1024 * 1024) {
        self.maximumCount = max(0, min(8, maximumCount))
        self.maximumBytes = max(0, min(128 * 1024 * 1024, maximumBytes))
    }
    public func image(forKey key: String) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[key] else { return nil }
        order.removeAll { $0 == key }; order.append(key)
        return entry.image
    }
    public func insert(_ image: CGImage, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        if let old = entries.removeValue(forKey: key) { bytes -= old.bytes }
        order.removeAll { $0 == key }
        let (cost, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !overflow, cost <= maximumBytes, maximumCount > 0 else { return }
        entries[key] = Entry(image: image, bytes: cost); order.append(key); bytes += cost
        while entries.count > maximumCount || bytes > maximumBytes {
            let oldest = order.removeFirst()
            if let old = entries.removeValue(forKey: oldest) { bytes -= old.bytes }
        }
    }
    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll(); order.removeAll(); bytes = 0
    }
}
