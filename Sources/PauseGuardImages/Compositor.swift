import Foundation
import CoreGraphics
import Accelerate

/// Pure synchronous renderer. Safe on a background executor; no AppKit or screen access.
/// Size is in output pixels, uniformly clamped to a 4096-pixel longest edge.
public enum Compositor {
    public static func render(selection: Selection, size: CGSize, libraryURL: URL) throws -> CGImage {
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1 else { throw ImageLibraryError.invalidSize }
        let ratio = min(1, 4096 / max(size.width, size.height))
        let width = max(1, Int(size.width * ratio)), height = max(1, Int(size.height * ratio))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ImageLibraryError.cannotCreateImage }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let w = CGFloat(width), h = CGFloat(height)
        context.setFillColor(CGColor(red: 0.025, green: 0.06, blue: 0.09, alpha: 1)); context.fill(bounds)
        // Load/decode one tile at a time. A missing asset is skipped; a wholly missing selection
        // still yields the dark, legible built-in background.
        let assets = Array(selection.assets.prefix(4))
        func draw(_ index: Int, _ rect: CGRect, blur: Double = 0, saturation: Double = 1, rotation: CGFloat = 0, frame: Bool = false) {
            guard !assets.isEmpty else { return }
            let pixelLimit = min(blur > 0 ? 1024 : 4096, max(1, Int(ceil(max(rect.width, rect.height)))))
            guard let decoded = try? ImageDecoding.load(assets[index % assets.count], libraryURL: libraryURL, maxPixel: pixelLimit),
                  let image = adjusted(decoded, blur: blur, saturation: saturation) else { return }
            context.saveGState()
            context.translateBy(x: rect.midX, y: rect.midY); context.rotate(by: rotation)
            let tile = CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
            if frame {
                context.setShadow(offset: CGSize(width: 0, height: -h * 0.02), blur: h * 0.04, color: CGColor(gray: 0, alpha: 0.65))
                context.setFillColor(CGColor(gray: 0.82, alpha: 1)); context.fill(tile.insetBy(dx: -w * 0.007, dy: -w * 0.007))
                context.setShadow(offset: .zero, blur: 0)
            }
            context.clip(to: tile)
            let scale = max(tile.width / CGFloat(image.width), tile.height / CGFloat(image.height))
            let destination = CGRect(x: -CGFloat(image.width) * scale / 2, y: -CGFloat(image.height) * scale / 2,
                width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            context.interpolationQuality = .high; context.draw(image, in: destination)
            context.restoreGState()
        }
        switch selection.layoutMode {
        case .hero, .random:
            // An opaque primary also provides a seamless single/missing-auxiliary fallback.
            draw(0, bounds)
            if assets.count > 1,
               let feather = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                   colors: [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 1)] as CFArray,
                   locations: [0, 1]) {
                let start = w * 0.64, end = w * 0.82
                context.saveGState()
                context.clip(to: CGRect(x: start, y: 0, width: w - start, height: h))
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                draw(1, CGRect(x: start, y: 0, width: w - start, height: h), blur: 3)
                // Mask only the auxiliary layer, so the overlap mixes photo colors without a dark wash.
                context.setBlendMode(.destinationIn)
                context.drawLinearGradient(feather, start: CGPoint(x: start, y: 0), end: CGPoint(x: end, y: 0),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                context.endTransparencyLayer()
                context.restoreGState()
            }
        case .grid:
            let gap = max(2, min(w, h) * 0.018)
            for index in 0..<4 {
                draw(index, CGRect(x: CGFloat(index % 2) * (w + gap) / 2, y: CGFloat(index / 2) * (h + gap) / 2, width: (w - gap) / 2, height: (h - gap) / 2))
            }
        case .collage:
            draw(0, bounds, blur: 24, saturation: 1)
            context.setFillColor(CGColor(red: 0.04, green: 0.08, blue: 0.1, alpha: 0.06)); context.fill(bounds)
            draw(0, CGRect(x: w * 0.025, y: h * 0.22, width: w * 0.36, height: h * 0.68), rotation: -0.12, frame: true)
            draw(1, CGRect(x: w * 0.62, y: h * 0.1, width: w * 0.34, height: h * 0.66), rotation: 0.13, frame: true)
            draw(2, CGRect(x: w * 0.35, y: h * 0.05, width: w * 0.3, height: h * 0.55), rotation: 0.04, frame: true)
        case .cinematic:
            draw(0, bounds, blur: 28, saturation: 1)
            context.setFillColor(CGColor(gray: 0, alpha: 0.08)); context.fill(bounds)
            draw(0, CGRect(x: 0, y: h * 0.16, width: w, height: h * 0.68), saturation: 1)
        case .minimal:
            draw(0, bounds, blur: 42, saturation: 1)
            context.setFillColor(CGColor(red: 0.03, green: 0.08, blue: 0.1, alpha: 0.06)); context.fill(bounds)
            let side = min(w * 0.31, h * 0.64)
            draw(0, CGRect(x: w * 0.69 - side / 2, y: h / 2 - side / 2, width: side, height: side), saturation: 1)
            context.setFillColor(CGColor(red: 0.5, green: 0.7, blue: 0.68, alpha: 0.6))
            context.fill(CGRect(x: w * 0.12, y: h * 0.72, width: w * 0.07, height: max(1, h * 0.006)))
        }
        guard let image = context.makeImage() else { throw ImageLibraryError.cannotCreateImage }
        return image
    }
    private static func adjusted(_ image: CGImage, blur: Double, saturation: Double) -> CGImage? {
        let width = image.width, height = image.height, row = width * 4
        var bytes = [UInt8](repeating: 0, count: row * height)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: row, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { return nil }
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let r = Double(bytes[index]), g = Double(bytes[index + 1]), b = Double(bytes[index + 2])
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let base = luminance * (1 - saturation)
            bytes[index] = UInt8(max(0, min(255, base + r * saturation)))
            bytes[index + 1] = UInt8(max(0, min(255, base + g * saturation)))
            bytes[index + 2] = UInt8(max(0, min(255, base + b * saturation)))
        }
        if blur > 0 {
            var output = [UInt8](repeating: 0, count: bytes.count)
            let kernel = UInt32(max(3, min(101, Int(blur) * 2 + 1))) | 1
            let status = bytes.withUnsafeMutableBytes { source in
                output.withUnsafeMutableBytes { destination in
                    var inputBuffer = vImage_Buffer(data: source.baseAddress!, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: row)
                    var outputBuffer = vImage_Buffer(data: destination.baseAddress!, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: row)
                    return vImageBoxConvolve_ARGB8888(&inputBuffer, &outputBuffer, nil, 0, 0, kernel, kernel, nil, vImage_Flags(kvImageEdgeExtend))
                }
            }
            if status == kvImageNoError { bytes = output }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: row,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
