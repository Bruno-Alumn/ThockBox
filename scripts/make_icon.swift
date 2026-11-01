// Build the Thockbox app icon from the logo artwork.
//
// Run via: swift scripts/make_icon.swift art/logo-source.png Resources/AppIcon.icns [docs/logo.png]
//
// The source is the logo tile on a white background. This finds the tile,
// scales it to the macOS icon grid (an 824 pt body inside a 1024 canvas),
// clips it to the standard rounded square (which also drops any white
// fringe), adds the usual soft shadow, and writes every size iconutil
// expects. Optionally also writes a 512 px PNG of the icon for the README.

import AppKit

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: make_icon.swift <logo.png> <AppIcon.icns> [preview.png]")
    exit(1)
}
guard let data = try? Data(contentsOf: URL(fileURLWithPath: args[1])),
      let source = NSBitmapImageRep(data: data) else {
    fatalError("can't read \(args[1])")
}

/// Bounds of everything that isn't the white background, in image pixels
/// (origin top-left, as stored).
func tileBounds(_ rep: NSBitmapImageRep) -> CGRect {
    var minX = rep.pixelsWide, maxX = 0, minY = rep.pixelsHigh, maxY = 0
    for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            if c.redComponent < 0.92 || c.greenComponent < 0.92 || c.blueComponent < 0.92 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let bounds = tileBounds(source)
guard let tile = source.cgImage?.cropping(to: bounds) else { fatalError("crop failed") }

func draw() {
    let tilePath = NSBezierPath(roundedRect: body, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor(srgbRed: 0, green: 0.4, blue: 0.43, alpha: 1).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    // Overscan a little so the source's own rounded corners and any white
    // edge fall outside the clip.
    let inset = body.insetBy(dx: -6, dy: -6)
    NSGraphicsContext.current?.cgContext.interpolationQuality = .high
    NSGraphicsContext.current?.cgContext.draw(tile, in: inset)
    NSGraphicsContext.restoreGraphicsState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Thockbox-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", args[2]]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("wrote \(args[2]) (tile \(Int(bounds.width))x\(Int(bounds.height)) px from \(args[1]))")

if args.count >= 4 {
    try png(size: 512).write(to: URL(fileURLWithPath: args[3]))
    print("wrote \(args[3])")
}
