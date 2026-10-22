// Draws the Islet app icon and writes an .iconset folder.
// Usage: swiftc scripts/make-icon.swift -o make-icon && ./make-icon <output-dir>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon"
let iconset = URL(fileURLWithPath: output).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Apple-style continuous rounded square (superellipse).
func squircle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n: CGFloat = 5.0
    let a = rect.width / 2, b = rect.height / 2
    let c = CGPoint(x: rect.midX, y: rect.midY)
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let x = c.x + a * (cos(t) >= 0 ? 1 : -1) * pow(abs(cos(t)), 2 / n)
        let y = c.y + b * (sin(t) >= 0 ? 1 : -1) * pow(abs(sin(t)), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func drawIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)
    ctx.interpolationQuality = .high

    // Body: macOS icon grid, 824 × 824 centred, with a soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: body)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x15131C))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    // Night-sky backdrop, lighter at the top like a lit screen edge.
    let backdrop = CGGradient(colorsSpace: srgb, colors: [color(0x3A2F5C), color(0x120F1A)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(backdrop, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Warm glow under the island.
    let glow = CGGradient(colorsSpace: srgb, colors: [color(0xFF5E8A, 0.55), color(0xFF5E8A, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 560), endRadius: 360, options: [])

    // The island: a black pill.
    let pill = CGRect(x: 192, y: 470, width: 640, height: 190)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: color(0x000000, 0.6))
    ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 95, cornerHeight: 95, transform: nil))
    ctx.setFillColor(color(0x000000))
    ctx.fillPath()
    ctx.restoreGState()

    // Artwork on the left.
    let art = CGRect(x: 240, y: 507, width: 116, height: 116)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: art, cornerWidth: 30, cornerHeight: 30, transform: nil))
    ctx.clip()
    let artGradient = CGGradient(colorsSpace: srgb, colors: [color(0xFFB347), color(0xFF4F7B), color(0x7B5CFF)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(artGradient, start: CGPoint(x: art.minX, y: art.maxY), end: CGPoint(x: art.maxX, y: art.minY), options: [])
    ctx.restoreGState()

    // Equaliser on the right.
    let heights: [CGFloat] = [70, 116, 52, 92]
    let barWidth: CGFloat = 22, gap: CGFloat = 16
    let startX: CGFloat = 784 - CGFloat(heights.count) * (barWidth + gap) + gap
    for (i, h) in heights.enumerated() {
        let rect = CGRect(x: startX + CGFloat(i) * (barWidth + gap), y: 565 - h / 2, width: barWidth, height: h)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 18, color: color(0xFF6A88, 0.9))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.setFillColor(color(0xFF7A90))
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.restoreGState()
    return ctx.makeImage()!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let rep = NSBitmapImageRep(cgImage: drawIcon(size: pixels))
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let preview = NSBitmapImageRep(cgImage: drawIcon(size: 512))
try! preview.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent("icon-preview.png"))
print("Wrote \(iconset.path)")
