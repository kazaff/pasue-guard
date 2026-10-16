import Testing
import SwiftUI
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PauseGuardApp

@Suite @MainActor struct GlassBackdropTests {
    // A photo-like low-frequency color field with fine stripes. A gray material
    // loses the color field; a sharp duplicate retains excessive stripe contrast.
    private func fixture(swapped: Bool = false, boundary: Int = 600) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8,
            bytesPerRow: 4800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for x in 0..<1200 {
            let red = (x < boundary) != swapped
            let stripe: CGFloat = x % 8 < 4 ? 1 : 0.55
            context.setFillColor(CGColor(red: red ? stripe : 0.04, green: 0.12, blue: red ? 0.04 : stripe, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: 800))
        }
        return try #require(context.makeImage())
    }
    private func render(_ image: CGImage, lowStimulation: Bool = false) throws -> [UInt8] {
        let scene = BreakPreviewScene(image: image, displaySize: CGSize(width: 1200, height: 800),
            reduceVisualStimulation: lowStimulation).frame(width: 1200, height: 800)

        return try pixels(scene)
    }
    private func pixels(_ view: some View) throws -> [UInt8] {
        let rendered = try #require(ImageRenderer(content: view).cgImage)
        var bytes = [UInt8](repeating: 0, count: 1200 * 800 * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1200, height: 800, bitsPerComponent: 8,
                bytesPerRow: 4800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(rendered, in: CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        return bytes
    }
    private func channel(_ bytes: [UInt8], x: Int, y: Int = 400, _ channel: Int) -> Double {
        Double(bytes[(y * 1200 + x) * 4 + channel])
    }
    @Test func panelRetainsAlignedPhotoColorsAndBlursFineDetail() throws {
        let a = try render(fixture())
        let b = try render(fixture(swapped: true))
        if let folder = ProcessInfo.processInfo.environment["PAUSEGUARD_GLASS_EXPORT_DIR"] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            for (name, pixels) in [("striped-red-blue", a), ("striped-blue-red", b)] {
                var bytes = pixels
                let image = bytes.withUnsafeMutableBytes { buffer in
                    CGContext(data: buffer.baseAddress, width: 1200, height: 800, bitsPerComponent: 8,
                        bytesPerRow: 4800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
                }
                let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".png")
                let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(destination, image, nil)
                #expect(CGImageDestinationFinalize(destination))
            }
        }
        let foregroundPixels = (250..<550).reduce(0) { total, y in
            total + (430..<770).filter { x in
                channel(a, x: x, y: y, 0) > 225 && channel(a, x: x, y: y, 1) > 225 && channel(a, x: x, y: y, 2) > 225
            }.count
        }
        #expect(foregroundPixels > 500, "Countdown and message must remain visible over the glass")
        // Panel's empty side padding: inside its bounds, outside all text/buttons.
        #expect(channel(a, x: 398, 0) - channel(a, x: 398, 2) > 65)
        #expect(channel(a, x: 802, 2) - channel(a, x: 802, 0) > 65)
        #expect(channel(b, x: 398, 2) - channel(b, x: 398, 0) > 65)
        #expect(channel(b, x: 802, 0) - channel(b, x: 802, 2) > 65)
        let fineContrast = abs(channel(a, x: 398, 0) - channel(a, x: 402, 0))
        let exposedContrast = abs(channel(a, x: 198, 0) - channel(a, x: 202, 0))
        #expect(exposedContrast > 60)
        #expect(fineContrast < exposedContrast * 0.3)
    }
    @Test func lowStimulationRemovesPhotoFromPanel() throws {
        let a = try render(fixture(), lowStimulation: true)
        let b = try render(fixture(swapped: true), lowStimulation: true)
        for x in [398, 802] {
            for c in 0..<3 { #expect(channel(a, x: x, c) == channel(b, x: x, c)) }
        }
    }
    @Test func frostUsesSceneCropAndMovingPanelOrigin() throws {
        // A square viewport crops 200px from each side of the 1200x800 image.
        // The panel is deliberately off-center; refitting the photo into the
        // panel or forgetting its origin would move the red/blue boundary away from scene x=100.
        let image = try fixture(boundary: 300)
        let backdrop = BreakPanelBackdrop(image: image, sceneSize: CGSize(width: 800, height: 800), reduceVisualStimulation: false)
        let view = ZStack(alignment: .topLeading) {
            BreakBackdrop(image: image, reduceVisualStimulation: false)
            BreakPanelFrost(backdrop: backdrop, reduceTransparency: false)
                .frame(width: 400, height: 600).offset(x: 50, y: 100)
        }
        .frame(width: 800, height: 800)
        .coordinateSpace(name: BreakPanelBackdrop.coordinateSpace)
        // Padding keeps the common pixel-buffer stride at 1200.
        .frame(width: 1200, height: 800, alignment: .leading)
        let bytes = try pixels(view)
        #expect(channel(bytes, x: 80, 0) - channel(bytes, x: 80, 2) > 65)
        #expect(channel(bytes, x: 150, 2) - channel(bytes, x: 150, 0) > 65)
    }
    @Test func reducedTransparencyFrostIsOpaqueAndPhotoIndependent() throws {
        func surface(_ image: CGImage) throws -> [UInt8] {
            let backdrop = BreakPanelBackdrop(image: image, sceneSize: CGSize(width: 1200, height: 800), reduceVisualStimulation: false)
            return try pixels(BreakPanelFrost(backdrop: backdrop, reduceTransparency: true)
                .frame(width: 1200, height: 800).coordinateSpace(name: BreakPanelBackdrop.coordinateSpace))
        }
        let a = try surface(fixture()), b = try surface(fixture(swapped: true))
        for x in [398, 802] {
            for c in 0..<4 { #expect(channel(a, x: x, c) == channel(b, x: x, c)) }
            #expect(channel(a, x: x, 3) == 255)
        }
    }
}
