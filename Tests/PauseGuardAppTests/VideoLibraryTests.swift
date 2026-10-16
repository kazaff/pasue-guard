import Testing
import Foundation
import AVFoundation
import CoreVideo
@testable import PauseGuardApp

struct VideoLibraryTests {
    private func movie(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for i in 0..<12 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            #expect(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess)
            let pixel = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixel, [])
            memset(CVPixelBufferGetBaseAddress(pixel), 180, CVPixelBufferGetDataSize(pixel))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            #expect(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(i), timescale: 12)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
    }
    @Test func validMovieIsCopiedAndSurvivesSourceRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mp4")
        try await movie(at: source)
        let library = VideoLibrary(directory: root.appendingPathComponent("Video"))
        let name = try await library.importVideo(source)
        try FileManager.default.removeItem(at: source)
        let imported = try #require(library.url(for: name))
        #expect(FileManager.default.fileExists(atPath: imported.path))
        #expect(!(try await AVURLAsset(url: imported).loadTracks(withMediaType: .video)).isEmpty)
    }
    @Test func brokenMovieDoesNotLeaveImportedFilesOrAllowTraversal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("broken.mp4")
        try Data("not a video".utf8).write(to: source)
        let library = VideoLibrary(directory: root.appendingPathComponent("Video"))
        await #expect(throws: (any Error).self) { _ = try await library.importVideo(source) }
        #expect(library.url(for: "../outside.mp4") == nil)
        #expect(library.url(for: "/tmp/outside.mp4") == nil)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: library.directory.path)) ?? []
        #expect(files.isEmpty)
    }
}

extension VideoLibraryTests {
    @Test @MainActor func playbackOwnsMutedMovieAndStopClearsDecoderAndFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("test.mp4")
        try await movie(at: source)
        let session = VideoPlayback()
        await session.start(source)
        #expect(!session.failed)
        #expect(session.player.isMuted)
        #expect(session.player.currentItem != nil)
        session.stop()
        #expect(session.player.currentItem == nil)
        #expect(session.frame == nil)
        await session.start(root.appendingPathComponent("missing.mp4"))
        #expect(session.failed)
        #expect(session.player.currentItem == nil)
        await session.start(nil)
        #expect(!session.failed)
        #expect(session.frame == nil)
    }
}
