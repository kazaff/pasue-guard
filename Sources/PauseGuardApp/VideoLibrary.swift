import Foundation
import AVFoundation

struct VideoLibrary: Sendable {
    let directory: URL
    enum ImportError: LocalizedError {
        case invalid
        var errorDescription: String? { "请选择包含可播放画面的本地 MP4 视频。" }
    }
    static func validate(_ url: URL) async throws {
        guard url.isFileURL, url.pathExtension.lowercased() == "mp4",
              (try FileManager.default.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeRegular else { throw ImportError.invalid }
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard playable, duration.seconds.isFinite, duration.seconds > 0, !tracks.isEmpty else { throw ImportError.invalid }
    }
    func importVideo(_ source: URL) async throws -> String {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        guard source.isFileURL, source.pathExtension.lowercased() == "mp4",
              (try FileManager.default.attributesOfItem(atPath: source.path)[.type]) as? FileAttributeType == .typeRegular else { throw ImportError.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let name = UUID().uuidString + ".mp4"
        let destination = directory.appendingPathComponent(name)
        do {
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.copyItem(at: source, to: destination)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            }.value
            try Task.checkCancellation()
            try await Self.validate(destination)
            try Task.checkCancellation()
            return name
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
    func url(for name: String?) -> URL? {
        guard let name, name == URL(fileURLWithPath: name).lastPathComponent, name.hasSuffix(".mp4") else { return nil }
        return directory.appendingPathComponent(name)
    }
}
