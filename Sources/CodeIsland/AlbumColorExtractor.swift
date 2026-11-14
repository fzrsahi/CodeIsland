import AppKit
import SwiftUI

/// Vibrant color palette extracted dynamically from music album artwork.
struct AlbumArtPalette: Equatable, Sendable {
    var primary: Color
    var secondary: Color
    var spectrum: RetroSpectrumPalette

    static let fallback = AlbumArtPalette(
        primary: Color(red: 0.0, green: 0.96, blue: 0.83), // Cyber Cyan
        secondary: Color(red: 1.0, green: 0.72, blue: 0.20), // Sunset Amber
        spectrum: RetroSpectrumPalette(
            base: Color(red: 0.0, green: 0.96, blue: 0.83),
            mid: Color(red: 0.0, green: 0.82, blue: 0.88),
            peak: Color(red: 0.70, green: 0.96, blue: 1.0)
        )
    )
}

/// High-performance, award-level vibrant color extraction for dark notch UI.
enum AlbumColorExtractor {
    /// Extracts a vibrant, high-contrast palette tuned specifically for dark notch UI.
    static func extractPalette(from image: NSImage) -> AlbumArtPalette {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .fallback
        }

        let targetWidth = 36
        let targetHeight = 36
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)

        guard let context = CGContext(
            data: &rawData,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .fallback
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        // 12 Hue Buckets (each spans 30 degrees = 1/12 of hue circle)
        var bucketWeights = [CGFloat](repeating: 0, count: 12)
        var bucketHues = [[CGFloat]](repeating: [], count: 12)
        var bucketSats = [[CGFloat]](repeating: [], count: 12)
        var bucketBrights = [[CGFloat]](repeating: [], count: 12)

        var fallbackBrightest: (h: CGFloat, s: CGFloat, b: CGFloat) = (0.55, 0.2, 0.9)

        let pixelCount = targetWidth * targetHeight
        for i in 0..<pixelCount {
            let offset = i * 4
            let r = CGFloat(rawData[offset]) / 255.0
            let g = CGFloat(rawData[offset + 1]) / 255.0
            let b = CGFloat(rawData[offset + 2]) / 255.0
            let a = CGFloat(rawData[offset + 3]) / 255.0

            guard a > 0.65 else { continue }

            var hue: CGFloat = 0
            var sat: CGFloat = 0
            var bright: CGFloat = 0
            let nsCol = NSColor(red: r, green: g, blue: b, alpha: 1.0)
            nsCol.getHue(&hue, saturation: &sat, brightness: &bright, alpha: nil)

            if bright > fallbackBrightest.b && sat > 0.1 {
                fallbackBrightest = (hue, sat, bright)
            }

            // Exclude extreme darks, pure blown whites, and muddy grays
            guard bright > 0.16, bright < 0.96, sat > 0.20 else { continue }

            let bucketIndex = min(11, max(0, Int(hue * 12.0)))
            // Vibrancy formula: heavily rewards saturated, vivid colors
            let weight = (sat * 1.8) + (bright * 0.9)

            bucketWeights[bucketIndex] += weight
            bucketHues[bucketIndex].append(hue)
            bucketSats[bucketIndex].append(sat)
            bucketBrights[bucketIndex].append(bright)
        }

        // Find primary dominant vibrant bucket
        var bestIndex = -1
        var bestWeight: CGFloat = 0
        for i in 0..<12 {
            if bucketWeights[i] > bestWeight {
                bestWeight = bucketWeights[i]
                bestIndex = i
            }
        }

        guard bestIndex >= 0, !bucketHues[bestIndex].isEmpty else {
            // Monochrome or low-saturation album: return clean ice cyan/silver
            let boosted = Color(hue: fallbackBrightest.h, saturation: min(0.35, fallbackBrightest.s), brightness: 0.95)
            return AlbumArtPalette(
                primary: boosted,
                secondary: Color(hue: (fallbackBrightest.h + 0.15).truncatingRemainder(dividingBy: 1.0), saturation: 0.35, brightness: 0.9),
                spectrum: RetroSpectrumPalette(
                    base: boosted,
                    mid: Color.white.opacity(0.8),
                    peak: Color(red: 0.0, green: 0.96, blue: 0.83)
                )
            )
        }

        // Calculate average hue, tuned for dark mode punch
        let count = CGFloat(bucketHues[bestIndex].count)
        let avgHue = bucketHues[bestIndex].reduce(0, +) / count
        let avgSat = bucketSats[bestIndex].reduce(0, +) / count
        let avgBright = bucketBrights[bestIndex].reduce(0, +) / count

        // PUNCH BOOST: Ensure color pops brightly on dark notch background (#0D0F14)
        let primaryHue = avgHue
        let primarySat = max(0.72, min(0.98, avgSat * 1.25))
        let primaryBright = max(0.80, min(0.98, avgBright * 1.20))
        let primaryColor = Color(hue: primaryHue, saturation: primarySat, brightness: primaryBright)

        // Find secondary contrast bucket at least 60 degrees away (2 buckets away)
        var secondBestIndex = -1
        var secondBestWeight: CGFloat = 0
        for i in 0..<12 {
            let dist = min(abs(i - bestIndex), 12 - abs(i - bestIndex))
            if dist >= 2 && bucketWeights[i] > secondBestWeight {
                secondBestWeight = bucketWeights[i]
                secondBestIndex = i
            }
        }

        let secondaryColor: Color
        let peakColor: Color

        if secondBestIndex >= 0, !bucketHues[secondBestIndex].isEmpty {
            let secCount = CGFloat(bucketHues[secondBestIndex].count)
            let secHue = bucketHues[secondBestIndex].reduce(0, +) / secCount
            let secSat = bucketSats[secondBestIndex].reduce(0, +) / secCount
            let secBright = bucketBrights[secondBestIndex].reduce(0, +) / secCount
            secondaryColor = Color(
                hue: secHue,
                saturation: max(0.70, min(0.98, secSat * 1.20)),
                brightness: max(0.82, min(0.98, secBright * 1.15))
            )
            peakColor = Color(
                hue: (secHue + 0.08).truncatingRemainder(dividingBy: 1.0),
                saturation: 0.85,
                brightness: 1.0
            )
        } else {
            // Harmonious analog/complementary shift
            let shiftedHue = (primaryHue + 0.15).truncatingRemainder(dividingBy: 1.0)
            secondaryColor = Color(hue: shiftedHue, saturation: 0.85, brightness: 0.95)
            peakColor = Color(
                hue: (shiftedHue + 0.12).truncatingRemainder(dividingBy: 1.0),
                saturation: 0.88,
                brightness: 1.0
            )
        }

        let spectrum = RetroSpectrumPalette(
            base: primaryColor,
            mid: secondaryColor,
            peak: peakColor
        )

        return AlbumArtPalette(
            primary: primaryColor,
            secondary: secondaryColor,
            spectrum: spectrum
        )
    }
}
