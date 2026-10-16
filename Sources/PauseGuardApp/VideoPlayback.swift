import AppKit
import SwiftUI
import AVFoundation
import CoreImage

/// Each cover owns its decoder; all covers read the same immutable local movie.
@MainActor final class VideoPlayback: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var frame: CGImage?
    @Published private(set) var failed = false
    private var output: AVPlayerItemVideoOutput?
    private var timer: Timer?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var revision = UUID()
    private var transform = CGAffineTransform.identity

    func start(_ url: URL?) async {
        stop()
        guard let url else { return }
        let token = revision
        do {
            try await VideoLibrary.validate(url)
            let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
            let transform = try await tracks.first?.load(.preferredTransform) ?? .identity
            guard !Task.isCancelled, revision == token else { return }
            self.transform = transform
            let item = AVPlayerItem(url: url)
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            item.add(output); self.output = output
            player.isMuted = true; player.actionAtItemEnd = .pause
            player.replaceCurrentItem(with: item)
            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.revision == token else { return }
                    self.player.pause(); self.frame = nil; self.failed = true
                }
            }
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.revision == token else { return }
                    self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                        Task { @MainActor [weak self] in
                            guard let self, finished, self.revision == token else { return }
                            self.player.play()
                        }
                    }
                }
            }
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sampleFrame() }
            }
            self.timer = timer; RunLoop.main.add(timer, forMode: .common)
            player.play()
        } catch {
            guard revision == token, !Task.isCancelled else { return }
            failed = true
        }
    }
    private func sampleFrame() {
        guard !failed, let output else { return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        let image = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
        // Bound the glass sampling cost; native video remains full resolution.
        let scale = min(1, 1280 / max(image.extent.width, image.extent.height))
        let reduced = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        frame = context.createCGImage(reduced, from: reduced.extent)
    }
    func stop() {
        revision = UUID()
        timer?.invalidate(); timer = nil
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.pause(); player.replaceCurrentItem(with: nil)
        output = nil; frame = nil; failed = false; transform = .identity
    }
    isolated deinit { stop() }
}

private final class MovieLayerView: NSView {
    let videoLayer = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        videoLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(videoLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer.frame = bounds; CATransaction.commit()
    }
}
struct MovieBackdropView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> NSView {
        let view = MovieLayerView(frame: .zero); view.videoLayer.player = player; return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { (nsView as? MovieLayerView)?.videoLayer.player = player }
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) { (nsView as? MovieLayerView)?.videoLayer.player = nil }
}
