import AppKit
import CoreImage

/// Picks an accent color from album art that reads well on pure black.
enum ArtworkColor {
    static func accent(for image: NSImage) -> NSColor {
        // Downsample to 24x24 and take the most saturated bright-ish pixels,
        // rather than the plain average (which tends toward muddy grey).
        let side = 24
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return .white }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx.data else { return .white }

        let px = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var best: [(h: CGFloat, s: CGFloat, b: CGFloat, score: CGFloat)] = []
        for i in 0..<(side * side) {
            let r = CGFloat(px[i * 4]) / 255, g = CGFloat(px[i * 4 + 1]) / 255, b = CGFloat(px[i * 4 + 2]) / 255
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
            NSColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: nil)
            // Favor saturated, not-too-dark pixels.
            let score = s * 0.7 + v * 0.3 - (v < 0.2 ? 1 : 0)
            best.append((h, s, v, score))
        }
        best.sort { $0.score > $1.score }
        let top = best.prefix(max(1, best.count / 8))

        // Average hue on the circle so reds near 0 and 1 don't cancel out.
        var x: CGFloat = 0, y: CGFloat = 0, s: CGFloat = 0
        for p in top {
            x += cos(p.h * 2 * .pi)
            y += sin(p.h * 2 * .pi)
            s += p.s
        }
        var hue = atan2(y, x) / (2 * .pi)
        if hue < 0 { hue += 1 }
        let sat = s / CGFloat(top.count)

        if sat < 0.15 { return NSColor(white: 0.92, alpha: 1) } // greyscale art
        return NSColor(hue: hue, saturation: min(max(sat, 0.45), 0.8), brightness: 0.95, alpha: 1)
    }
}

/// Pre-renders the ambient glow: the cover shrunk to a few pixels, blurred and
/// saturated once, off the main thread. Displaying it scaled up is then just a
/// bitmap stretch, so drifting it every frame costs nothing (a live SwiftUI
/// blur on a large image would re-filter on every transform change).
enum ArtworkAura {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func make(from image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cg)
        let scale = 48 / max(input.extent.width, input.extent.height)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 5])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5, kCIInputBrightnessKey: 0.02])
            .cropped(to: small.extent)
        guard let out = context.createCGImage(blurred, from: small.extent) else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
    }
}
