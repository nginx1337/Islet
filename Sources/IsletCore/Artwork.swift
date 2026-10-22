import CoreGraphics
import Foundation
import ImageIO

/// sRGB colour with components in 0…1.
public struct SRGBColor: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hue: Double, saturation: Double, brightness: Double) {
        let h = (hue - floor(hue)) * 6, s = saturation, v = brightness
        let i = Int(h) % 6, f = h - floor(h)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: (red, green, blue) = (v, t, p)
        case 1: (red, green, blue) = (q, v, p)
        case 2: (red, green, blue) = (p, v, t)
        case 3: (red, green, blue) = (p, q, v)
        case 4: (red, green, blue) = (t, p, v)
        default: (red, green, blue) = (v, p, q)
        }
    }

    /// (hue 0…1, saturation, brightness)
    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxC = max(red, green, blue), minC = min(red, green, blue), delta = maxC - minC
        var hue = 0.0
        if delta > 0 {
            if maxC == red { hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == green { hue = (blue - red) / delta + 2 }
            else { hue = (red - green) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maxC == 0 ? 0 : delta / maxC, maxC)
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }

    public static let neutral = SRGBColor(red: 0.92, green: 0.92, blue: 0.94)
}

/// Accent colour of an artwork: the most saturated of the frequent colours, made bright enough for black.
public enum DominantColor {
    public static let sampleSize = 16

    /// Returns `nil` when the picture is (almost) grey; callers then use ``SRGBColor/neutral``.
    public static func accent(of image: CGImage) -> SRGBColor? {
        guard let raw = pick(from: samplePixels(of: image)) else { return nil }
        return adjustedForBlackBackground(raw)
    }

    /// Draws the image into 16×16 sRGB pixels.
    public static func samplePixels(of image: CGImage) -> [SRGBColor] {
        let n = sampleSize
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard drawn else { return [] }
        var pixels: [SRGBColor] = []
        pixels.reserveCapacity(n * n)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let a = Double(bytes[i + 3]) / 255
            guard a > 0.5 else { continue }
            pixels.append(SRGBColor(
                red: Double(bytes[i]) / 255 / a, green: Double(bytes[i + 1]) / 255 / a, blue: Double(bytes[i + 2]) / 255 / a))
        }
        return pixels
    }

    /// Groups colourful pixels by hue and returns the average colour of the best group.
    /// Score = how many pixels × how saturated they are, so a small vivid patch beats a big dull one
    /// only when it is not tiny.
    public static func pick(from pixels: [SRGBColor]) -> SRGBColor? {
        struct Bucket { var count = 0; var r = 0.0, g = 0.0, b = 0.0, s = 0.0 }
        var buckets: [Int: Bucket] = [:]
        for p in pixels {
            let (h, s, v) = p.hsb
            // Skip greys, near-black and near-white: they say nothing about the artwork's colour.
            guard s >= 0.2, v >= 0.15 else { continue }
            let key = Int(h * 12) % 12 * 2 + (s >= 0.55 ? 1 : 0)
            var bucket = buckets[key, default: Bucket()]
            bucket.count += 1
            bucket.r += p.red; bucket.g += p.green; bucket.b += p.blue; bucket.s += s
            buckets[key] = bucket
        }
        let minimum = max(2, pixels.count / 40)
        let best = buckets.values
            .filter { $0.count >= minimum }
            .max { a, b in
                Double(a.count) * (a.s / Double(a.count)) < Double(b.count) * (b.s / Double(b.count))
            }
        guard let best else { return nil }
        let n = Double(best.count)
        return SRGBColor(red: best.r / n, green: best.g / n, blue: best.b / n)
    }

    /// Raises brightness (and trims saturation if needed) until the colour reads well on black.
    public static func adjustedForBlackBackground(_ color: SRGBColor) -> SRGBColor {
        let hsb = color.hsb
        var s = min(hsb.saturation, 0.85)
        var v = max(hsb.brightness, 0.82)
        var result = SRGBColor(hue: hsb.hue, saturation: s, brightness: v)
        while result.luminance < 0.28 && s > 0.25 {
            s -= 0.05
            v = min(1, v + 0.02)
            result = SRGBColor(hue: hsb.hue, saturation: s, brightness: v)
        }
        return result
    }
}

/// Decodes artwork bytes into a small bitmap (long side ≤ `maxPixelSize`).
public enum ArtworkDecoder {
    public static let maxPixelSize = 256

    public static func thumbnail(from data: Data, maxPixelSize: Int = ArtworkDecoder.maxPixelSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Small least-recently-used cache (artwork thumbnails: last 20).
public struct LRUCache<Key: Hashable, Value> {
    public let capacity: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { values.count }
    /// Keys from least to most recently used.
    public var keys: [Key] { order }

    public mutating func value(for key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    public mutating func insert(_ value: Value, for key: Key) {
        values[key] = value
        touch(key)
        while order.count > capacity {
            values.removeValue(forKey: order.removeFirst())
        }
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
