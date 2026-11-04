import AppKit
import Foundation

// Original MemoLine artwork, drawn from geometric shapes. No upstream assets.
let destination = CommandLine.arguments.dropFirst().first ?? "build/MemoLine.iconset"
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "MemoLine.Icon", code: 1)
        }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 208, yRadius: 208)
        NSColor(calibratedRed: 0.13, green: 0.29, blue: 0.32, alpha: 1).setFill(); tile.fill()
        let rope = NSBezierPath(); rope.move(to: NSPoint(x: 105, y: 738))
        rope.curve(to: NSPoint(x: 919, y: 738), controlPoint1: NSPoint(x: 330, y: 665), controlPoint2: NSPoint(x: 695, y: 665))
        NSColor(calibratedWhite: 0.91, alpha: 0.8).setStroke(); rope.lineWidth = 12; rope.stroke()
        let paper = NSBezierPath(roundedRect: NSRect(x: 274, y: 242, width: 476, height: 458), xRadius: 38, yRadius: 38)
        NSColor(calibratedRed: 0.99, green: 0.91, blue: 0.66, alpha: 1).setFill(); paper.fill()
        let clip = NSBezierPath(roundedRect: NSRect(x: 487, y: 644, width: 50, height: 132), xRadius: 15, yRadius: 15)
        NSColor(calibratedWhite: 0.89, alpha: 1).setFill(); clip.fill()
        NSColor(calibratedRed: 0.27, green: 0.38, blue: 0.32, alpha: 1).setStroke()
        for (y, width): (CGFloat, CGFloat) in [(542, 280), (454, 280), (366, 178)] {
            let line = NSBezierPath(); line.move(to: NSPoint(x: 360, y: y)); line.line(to: NSPoint(x: 360 + width, y: y))
            line.lineCapStyle = .round; line.lineWidth = 22; line.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "MemoLine.Icon", code: 2) }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: URL(fileURLWithPath: destination).appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
