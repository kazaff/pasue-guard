import Foundation

/// Best-effort diagnostics; I/O failure never changes timer enforcement.
public final class EventLog: @unchecked Sendable {
    private let directory: URL
    private let maximumBytes: Int
    private let lock = NSLock()
    public init(directory: URL = StateStore.defaultDirectory, maximumBytes: Int = 262_144) {
        self.directory = directory
        self.maximumBytes = max(256, min(maximumBytes, 1_048_576))
    }
    public func append(kind: String, detail: String) {
        lock.lock()
        defer { lock.unlock() }
        let url = directory.appendingPathComponent("events.log")
        let clean: (String) -> String = { $0.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") }
        let line = "\(Date().timeIntervalSince1970) \(clean(kind)) \(clean(detail))\n"
        var addition = Data(line.utf8)
        if addition.count > maximumBytes {
            addition = Data("event truncated\n".utf8)
        }
        var existing = (try? PrivateFiles.read(url)) ?? Data()
        if existing.count + addition.count > maximumBytes {
            let excess = existing.count + addition.count - maximumBytes
            existing.removeFirst(min(excess, existing.count))
            if let newline = existing.firstIndex(of: 10) { existing.removeSubrange(...newline) }
            else { existing.removeAll() }
        }
        existing.append(addition)
        try? PrivateFiles.write(existing, to: url)
    }
}
