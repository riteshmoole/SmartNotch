// Draws the SmartNotch app icon (original artwork) at every iconset size.
import AppKit

let out = CommandLine.arguments[1]
let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                              ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]

func draw(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.225
    // Squircle background: deep indigo → black
    let bg = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.18, blue: 0.36, alpha: 1), NSColor(red: 0.03, green: 0.03, blue: 0.08, alpha: 1)])!
        .draw(in: bg, angle: -90)
    // Screen bezel line
    NSColor(white: 1, alpha: 0.08).setStroke()
    bg.lineWidth = max(1, s * 0.006)
    bg.stroke()
    // The island: a black capsule hanging from the top, with a soft blue glow
    let iw = body.width * 0.62, ih = body.height * 0.2
    let island = NSRect(x: body.midX - iw / 2, y: body.maxY - body.height * 0.17 - ih, width: iw, height: ih)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.06, color: NSColor(red: 0.04, green: 0.52, blue: 1, alpha: 0.9).cgColor)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: island, xRadius: ih / 2, yRadius: ih / 2).fill()
    ctx.restoreGState()
    // Artwork dot + equalizer bars inside the island
    let dot = ih * 0.56
    NSGradient(colors: [NSColor(red: 1, green: 0.42, blue: 0.17, alpha: 1), NSColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 1)])!
        .draw(in: NSBezierPath(roundedRect: NSRect(x: island.minX + ih * 0.3, y: island.midY - dot / 2, width: dot, height: dot),
                               xRadius: dot * 0.28, yRadius: dot * 0.28), angle: 45)
    NSColor(red: 0.04, green: 0.52, blue: 1, alpha: 1).setFill()
    let heights: [CGFloat] = [0.35, 0.7, 0.5, 0.85]
    let bw = ih * 0.11
    for (i, h) in heights.enumerated() {
        let x = island.maxX - ih * 0.35 - CGFloat(heights.count - i) * bw * 1.8
        let bh = ih * 0.6 * h
        NSBezierPath(roundedRect: NSRect(x: x, y: island.midY - bh / 2, width: bw, height: bh), xRadius: bw / 2, yRadius: bw / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in sizes {
    try! draw(px).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
