import AppKit

/// Four rounded bars, drawn as a template image. Idle: a calm static glyph.
/// Listening: bars follow the input level with a gentle wave, so the icon pulses.
enum MenuBarIcon {
    static func image(active: Bool, level: Float, phase: Double) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let barWidth: CGFloat = 2.6
            let gap: CGFloat = 1.9
            let count = 4
            let total = CGFloat(count) * barWidth + CGFloat(count - 1) * gap
            var x = (rect.width - total) / 2
            let idleHeights: [CGFloat] = [0.45, 0.85, 0.65, 0.35]
            for i in 0..<count {
                let fraction: CGFloat
                if active {
                    let wave = (sin(phase * 2 * .pi * 0.9 + Double(i) * 1.4) + 1) / 2
                    let l = Double(min(max(level, 0), 1))
                    fraction = CGFloat(0.3 + 0.7 * min(1, l * (0.55 + 0.45 * wave) + 0.22 * wave))
                } else {
                    fraction = idleHeights[i]
                }
                let height = max(barWidth, (rect.height - 2) * fraction)
                let bar = NSRect(x: x, y: (rect.height - height) / 2, width: barWidth, height: height)
                NSColor.black.setFill()
                NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
                x += barWidth + gap
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
