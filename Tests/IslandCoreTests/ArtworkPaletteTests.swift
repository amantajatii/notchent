import CoreGraphics
import Foundation
import Testing
@testable import IslandCore

private func makeImage(width: Int = 40, height: Int = 40, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage? {
    var data = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let (r, g, b) = pixel(x, y)
            let i = (y * width + x) * 4
            data[i] = r; data[i + 1] = g; data[i + 2] = b
        }
    }
    guard let provider = CGDataProvider(data: Data(data) as CFData),
          let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )
}

private func isWithinUnitRange(_ c: PaletteColor) -> Bool {
    [c.red, c.green, c.blue].allSatisfy { (0...1).contains($0) }
}

struct ArtworkPaletteTests {
    @Test func solidRedYieldsRedPrimary() throws {
        let image = try #require(makeImage { _, _ in (220, 20, 20) })
        let palette = try #require(ArtworkPalette.extract(from: image))
        #expect(palette.primary.red > palette.primary.green)
        #expect(palette.primary.red > palette.primary.blue)
    }

    @Test func blueAndOrangeHalvesGiveTwoDistinctHues() throws {
        let image = try #require(makeImage { x, _ in x < 20 ? (20, 60, 230) : (255, 140, 20) })
        let palette = try #require(ArtworkPalette.extract(from: image))
        let colors = [palette.primary, palette.secondary]
        #expect(colors.contains { $0.blue > $0.red })
        #expect(colors.contains { $0.red > $0.blue })
        #expect(palette.primary != palette.secondary)
    }

    @Test func darkGreyAndBlackFallBackToNeutral() throws {
        let neutral = PaletteColor(red: 0.85, green: 0.85, blue: 0.9)
        for value in [UInt8(0), 30, 128] {
            let image = try #require(makeImage { _, _ in (value, value, value) })
            let palette = try #require(ArtworkPalette.extract(from: image))
            #expect(palette.primary == neutral)
            #expect(palette.secondary == neutral)
        }
    }

    @Test func componentsStayWithinUnitRange() throws {
        let image = try #require(makeImage { x, y in (UInt8(x * 6), UInt8(y * 6), UInt8((x + y) * 3)) })
        let palette = try #require(ArtworkPalette.extract(from: image))
        #expect(isWithinUnitRange(palette.primary))
        #expect(isWithinUnitRange(palette.secondary))
    }
}
