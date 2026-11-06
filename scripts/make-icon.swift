// Renders Resources/AppIcon.icns: a dark squircle with 听 and a small level meter.
//   swift scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS icon grid: 824/1024 body with shadow room.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.225
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.17, blue: 0.24, alpha: 1),
                        NSColor(srgbRed: 0.05, green: 0.05, blue: 0.09, alpha: 1)])!
        .draw(in: body, angle: -90)
    // soft glow behind the glyph
    NSGradient(colors: [NSColor(srgbRed: 0.35, green: 0.55, blue: 1, alpha: 0.35), .clear])!
        .draw(fromCenter: NSPoint(x: body.midX, y: body.midY + body.height * 0.06), radius: 0,
              toCenter: NSPoint(x: body.midX, y: body.midY + body.height * 0.06), radius: body.width * 0.5, options: [])

    // 听
    let font = NSFont(name: "PingFangSC-Semibold", size: body.width * 0.48) ?? .systemFont(ofSize: body.width * 0.48, weight: .semibold)
    let glyph = NSAttributedString(string: "听", attributes: [.font: font, .foregroundColor: NSColor.white])
    let g = glyph.size()
    glyph.draw(at: NSPoint(x: body.midX - g.width / 2, y: body.midY - g.height / 2 + body.height * 0.08))

    // level meter under the glyph
    let heights: [CGFloat] = [0.35, 0.7, 1, 0.55, 0.8, 0.4, 0.6]
    let barW = body.width * 0.04, gap = body.width * 0.035, maxH = body.height * 0.13
    let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
    var x = body.midX - total / 2
    let baseY = body.minY + body.height * 0.19
    for h in heights {
        let r = NSRect(x: x, y: baseY + (maxH - maxH * h) / 2, width: barW, height: maxH * h)
        NSColor(srgbRed: 0.55, green: 0.75, blue: 1, alpha: 0.95).setFill()
        NSBezierPath(roundedRect: r, xRadius: barW / 2, yRadius: barW / 2).fill()
        x += barW + gap
    }
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
try! render(1024).write(to: URL(fileURLWithPath: "/tmp/tingjian-icon-preview.png"))
print("wrote \(out.path)")
