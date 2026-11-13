import CoreGraphics
import Foundation

public struct PaletteColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct ArtworkPalette: Equatable, Sendable {
    public let primary: PaletteColor
    public let secondary: PaletteColor
    public init(primary: PaletteColor, secondary: PaletteColor) {
        self.primary = primary
        self.secondary = secondary
    }

    private static let sampleSize = 24
    private static let bucketCount = 12
    private static let minBrightness = 0.15
    private static let minSaturation = 0.18
    private static let minHueSeparation = 60.0
    private static let vividSaturation = 0.55
    private static let vividBrightness = 0.75
    private static let neutral = PaletteColor(red: 0.85, green: 0.85, blue: 0.9)

    private struct Bucket {
        var weight = 0.0
        var red = 0.0
        var green = 0.0
        var blue = 0.0
    }

    /// nil when the image cannot be read. Never nil for a readable but grey image: then returns a neutral soft white pair.
    public static func extract(from image: CGImage) -> ArtworkPalette? {
        guard let pixels = samplePixels(image) else { return nil }
        let buckets = bucketize(pixels)
        guard let top = heaviest(buckets, excluding: nil) else {
            return ArtworkPalette(primary: neutral, secondary: neutral)
        }
        let second = heaviest(buckets, excluding: top) ?? top
        return ArtworkPalette(primary: vivify(color(of: buckets[top])), secondary: vivify(color(of: buckets[second])))
    }

    private static func samplePixels(_ image: CGImage) -> [UInt8]? {
        let size = sampleSize
        var data = [UInt8](repeating: 0, count: size * size * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        return drawn ? data : nil
    }

    private static func bucketize(_ data: [UInt8]) -> [Bucket] {
        var buckets = [Bucket](repeating: Bucket(), count: bucketCount)
        for offset in stride(from: 0, to: data.count, by: 4) {
            let alpha = Double(data[offset + 3]) / 255
            guard alpha > 0 else { continue }
            let r = min(1, Double(data[offset]) / 255 / alpha)
            let g = min(1, Double(data[offset + 1]) / 255 / alpha)
            let b = min(1, Double(data[offset + 2]) / 255 / alpha)
            let (hue, sat, bri) = toHSB(r, g, b)
            guard bri >= minBrightness, sat >= minSaturation else { continue }
            let index = min(bucketCount - 1, Int(hue / 360 * Double(bucketCount)))
            let weight = sat * bri
            buckets[index].weight += weight
            buckets[index].red += r * weight
            buckets[index].green += g * weight
            buckets[index].blue += b * weight
        }
        return buckets
    }

    private static func heaviest(_ buckets: [Bucket], excluding primary: Int?) -> Int? {
        let width = 360.0 / Double(bucketCount)
        var best: Int?
        for (index, bucket) in buckets.enumerated() where bucket.weight > 0 {
            if let primary {
                let delta = abs(Double(index - primary)) * width
                if min(delta, 360 - delta) < minHueSeparation { continue }
            }
            if best == nil || bucket.weight > buckets[best ?? 0].weight { best = index }
        }
        return best
    }

    private static func color(of bucket: Bucket) -> PaletteColor {
        PaletteColor(red: bucket.red / bucket.weight, green: bucket.green / bucket.weight, blue: bucket.blue / bucket.weight)
    }

    private static func vivify(_ color: PaletteColor) -> PaletteColor {
        let (hue, sat, bri) = toHSB(color.red, color.green, color.blue)
        return fromHSB(hue, max(sat, vividSaturation), max(bri, vividBrightness))
    }

    private static func toHSB(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        guard delta > 0 else { return (0, 0, maxC) }
        var hue: Double
        if maxC == r { hue = (g - b) / delta } else if maxC == g { hue = (b - r) / delta + 2 } else { hue = (r - g) / delta + 4 }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, delta / maxC, maxC)
    }

    private static func fromHSB(_ hue: Double, _ sat: Double, _ bri: Double) -> PaletteColor {
        let sector = hue / 60
        let chroma = bri * sat
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let m = bri - chroma
        let rgb: (Double, Double, Double)
        switch Int(sector) % 6 {
        case 0: rgb = (chroma, x, 0)
        case 1: rgb = (x, chroma, 0)
        case 2: rgb = (0, chroma, x)
        case 3: rgb = (0, x, chroma)
        case 4: rgb = (x, 0, chroma)
        default: rgb = (chroma, 0, x)
        }
        return PaletteColor(red: min(1, rgb.0 + m), green: min(1, rgb.1 + m), blue: min(1, rgb.2 + m))
    }
}
