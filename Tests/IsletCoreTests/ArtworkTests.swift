import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import IsletCore

@Suite("Artwork colour and cache")
struct ArtworkTests {
    /// Draws a synthetic "album cover": a background with optional rectangles on top.
    static func image(size: Int = 64, background: (Double, Double, Double), patches: [(CGRect, (Double, Double, Double))] = []) -> CGImage {
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: background.0, green: background.1, blue: background.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        for (rect, c) in patches {
            ctx.setFillColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
            ctx.fill(rect)
        }
        return ctx.makeImage()!
    }

    static func hue(_ color: SRGBColor) -> Double { color.hsb.hue * 360 }

    @Test func picksTheSaturatedColourOverGrey() throws {
        // Mostly grey cover with a red block on a quarter of it.
        let img = Self.image(background: (0.5, 0.5, 0.5), patches: [(CGRect(x: 0, y: 0, width: 32, height: 32), (0.85, 0.1, 0.1))])
        let accent = try #require(DominantColor.accent(of: img))
        #expect(Self.hue(accent) < 15 || Self.hue(accent) > 345, "red")
    }

    @Test func frequentBeatsTinyVividPatch() throws {
        // Big muted-blue area, tiny vivid yellow dot (1/64 of the area).
        let img = Self.image(background: (0.2, 0.3, 0.6), patches: [(CGRect(x: 0, y: 0, width: 8, height: 8), (1, 0.9, 0))])
        let accent = try #require(DominantColor.accent(of: img))
        let h = Self.hue(accent)
        #expect(h > 200 && h < 240, "blue, got \(h)")
    }

    @Test func moreSaturatedWinsAmongFrequentColours() throws {
        // Half dull green, half vivid orange.
        let img = Self.image(background: (0.45, 0.6, 0.45), patches: [(CGRect(x: 0, y: 0, width: 64, height: 32), (1, 0.5, 0))])
        let accent = try #require(DominantColor.accent(of: img))
        let h = Self.hue(accent)
        #expect(h > 20 && h < 40, "orange, got \(h)")
    }

    @Test func darkColourIsBrightenedForBlackBackground() throws {
        let img = Self.image(background: (0.05, 0.05, 0.3))
        let accent = try #require(DominantColor.accent(of: img))
        #expect(accent.hsb.brightness >= 0.82)
        #expect(accent.luminance >= 0.2)
        let h = Self.hue(accent)
        #expect(h > 225 && h < 255, "still blue, got \(h)")
    }

    @Test func greyscaleHasNoAccent() {
        #expect(DominantColor.accent(of: Self.image(background: (0.3, 0.3, 0.3))) == nil)
        #expect(DominantColor.accent(of: Self.image(background: (0, 0, 0), patches: [(CGRect(x: 0, y: 0, width: 32, height: 64), (1, 1, 1))])) == nil)
    }

    @Test func samplesAt16x16() {
        #expect(DominantColor.samplePixels(of: Self.image(size: 300, background: (1, 0, 0))).count == 256)
    }

    @Test func hsbRoundTrip() {
        let c = SRGBColor(red: 0.2, green: 0.6, blue: 0.9)
        let (h, s, v) = c.hsb
        let back = SRGBColor(hue: h, saturation: s, brightness: v)
        #expect(abs(back.red - c.red) < 0.0001 && abs(back.green - c.green) < 0.0001 && abs(back.blue - c.blue) < 0.0001)
    }

    @Test func thumbnailIsAtMost256Pixels() throws {
        let big = Self.image(size: 1000, background: (0.1, 0.7, 0.3))
        let data = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, big, nil)
        #expect(CGImageDestinationFinalize(dest))
        let thumb = try #require(ArtworkDecoder.thumbnail(from: data as Data))
        #expect(max(thumb.width, thumb.height) == 256)
        #expect(ArtworkDecoder.thumbnail(from: Data([1, 2, 3])) == nil, "garbage does not crash")
    }

    @Test func lruKeepsTheLast20() {
        var cache = LRUCache<String, Int>(capacity: 20)
        for i in 0..<25 { cache.insert(i, for: "k\(i)") }
        #expect(cache.count == 20)
        #expect(cache.value(for: "k0") == nil)
        #expect(cache.value(for: "k5") == 5)
        cache.insert(99, for: "new")
        #expect(cache.value(for: "k5") == 5, "recently read entries survive")
        #expect(cache.value(for: "k6") == nil, "the least recently used one goes")
    }
}
