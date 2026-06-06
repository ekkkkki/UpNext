import AppKit
import CoreGraphics

// Renders UpNext's app icon (gradient squircle + white "+") into an .iconset
// directory. Pure CoreGraphics so it runs under Command Line Tools with no
// NSApplication. Usage: swift make_icon.swift <iconset-dir>

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: make_icon <iconset-dir>\n".data(using: .utf8)!)
    exit(2)
}
let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let s = CGFloat(px)

    // Rounded "squircle" body with a diagonal gradient.
    let inset = s * 0.045
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.2237
    let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    cg.saveGState()
    cg.addPath(path); cg.clip()
    let colors = [
        CGColor(red: 0.36, green: 0.55, blue: 0.97, alpha: 1.0),
        CGColor(red: 0.60, green: 0.35, blue: 0.91, alpha: 1.0)
    ] as CFArray
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    }
    cg.restoreGState()

    // White rounded "+".
    let thickness = s * 0.12
    let length = s * 0.46
    cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    let horizontal = CGRect(x: (s - length) / 2, y: (s - thickness) / 2, width: length, height: thickness)
    let vertical = CGRect(x: (s - thickness) / 2, y: (s - length) / 2, width: thickness, height: length)
    cg.addPath(CGPath(roundedRect: horizontal, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil))
    cg.addPath(CGPath(roundedRect: vertical, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil))
    cg.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for (name, px) in sizes {
    guard let data = render(px) else {
        FileHandle.standardError.write("failed to render \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
    try? data.write(to: url)
}
print("wrote \(sizes.count) icon sizes to \(outDir)")
