import SwiftUI

public struct DioramaSkyPalette {
    private struct RGB {
        var r: Double
        var g: Double
        var b: Double
        var color: Color { Color(red: r, green: g, blue: b) }
    }

    private static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
    }

    private static let keys: [(h: Double, top: RGB, bottom: RGB)] = [
        (0.0,  RGB(r: 0.07, g: 0.07, b: 0.18), RGB(r: 0.16, g: 0.13, b: 0.28)),
        (4.5,  RGB(r: 0.08, g: 0.08, b: 0.22), RGB(r: 0.22, g: 0.16, b: 0.34)),
        (5.5,  RGB(r: 0.16, g: 0.20, b: 0.42), RGB(r: 0.95, g: 0.55, b: 0.40)),
        (7.5,  RGB(r: 0.45, g: 0.72, b: 0.95), RGB(r: 0.98, g: 0.85, b: 0.62)),
        (12.0, RGB(r: 0.30, g: 0.62, b: 0.98), RGB(r: 0.62, g: 0.84, b: 1.00)),
        (16.0, RGB(r: 0.40, g: 0.55, b: 0.85), RGB(r: 1.00, g: 0.78, b: 0.45)),
        (18.3, RGB(r: 0.30, g: 0.22, b: 0.45), RGB(r: 1.00, g: 0.42, b: 0.22)),
        (19.6, RGB(r: 0.11, g: 0.10, b: 0.26), RGB(r: 0.26, g: 0.18, b: 0.38)),
        (21.5, RGB(r: 0.09, g: 0.09, b: 0.22), RGB(r: 0.20, g: 0.16, b: 0.32)),
        (24.0, RGB(r: 0.07, g: 0.07, b: 0.18), RGB(r: 0.16, g: 0.13, b: 0.28)),
    ]

    public static func colors(_ hour: Double) -> (Color, Color) {
        let h = hour.truncatingRemainder(dividingBy: 24)
        for i in 1..<keys.count where h <= keys[i].h {
            let a = keys[i - 1], b = keys[i]
            let t = (h - a.h) / (b.h - a.h)
            return (mix(a.top, b.top, t).color, mix(a.bottom, b.bottom, t).color)
        }
        return (keys[0].top.color, keys[0].bottom.color)
    }

    public static func pixelBands(_ hour: Double) -> [Color] {
        let h = hour.truncatingRemainder(dividingBy: 24)
        if h >= 4.5 && h < 6.0 {
            // Subuh / Fajar: Deep Indigo -> Twilight Violet -> Deep Rose -> Dawn Amber
            return [
                Color(red: 0.05, green: 0.06, blue: 0.15),
                Color(red: 0.18, green: 0.08, blue: 0.30),
                Color(red: 0.45, green: 0.12, blue: 0.35),
                Color(red: 0.85, green: 0.42, blue: 0.28)
            ]
        } else if h >= 6.0 && h < 11.5 {
            // Pagi / Morning: Vivid Azure -> Retro Cyan Sky -> Bright Cyan -> Soft Warm Horizon
            return [
                Color(red: 0.12, green: 0.35, blue: 0.82),
                Color(red: 0.20, green: 0.55, blue: 0.95),
                Color(red: 0.40, green: 0.75, blue: 0.98),
                Color(red: 0.82, green: 0.92, blue: 0.98)
            ]
        } else if h >= 11.5 && h < 15.0 {
            // Dzuhur / Midday: Royal 8-bit Blue -> Sky Blue -> Cyan Horizon
            return [
                Color(red: 0.10, green: 0.30, blue: 0.78),
                Color(red: 0.18, green: 0.48, blue: 0.92),
                Color(red: 0.32, green: 0.70, blue: 0.96),
                Color(red: 0.65, green: 0.88, blue: 0.98)
            ]
        } else if h >= 15.0 && h < 17.5 {
            // Ashar / Late Afternoon: Azure -> Warm Amber -> Golden Ochre -> Warm Peach
            return [
                Color(red: 0.15, green: 0.32, blue: 0.75),
                Color(red: 0.55, green: 0.40, blue: 0.65),
                Color(red: 0.88, green: 0.55, blue: 0.25),
                Color(red: 0.98, green: 0.82, blue: 0.50)
            ]
        } else if h >= 17.5 && h < 19.3 {
            // Maghrib / Sunset: Deep Purple -> Crimson Red -> Sunset Orange -> Golden Horizon
            return [
                Color(red: 0.18, green: 0.05, blue: 0.28),
                Color(red: 0.55, green: 0.10, blue: 0.22),
                Color(red: 0.90, green: 0.35, blue: 0.12),
                Color(red: 0.98, green: 0.72, blue: 0.20)
            ]
        } else {
            // Isya / Midnight: Pitch Void -> Deep Navy -> Midnight Slate -> Horizon Night
            return [
                Color(red: 0.02, green: 0.03, blue: 0.08),
                Color(red: 0.05, green: 0.07, blue: 0.16),
                Color(red: 0.09, green: 0.12, blue: 0.24),
                Color(red: 0.14, green: 0.18, blue: 0.32)
            ]
        }
    }

    public static func nightFactor(_ hour: Double) -> Double {
        let h = hour.truncatingRemainder(dividingBy: 24)
        if h < 4.5 || h > 19.8 { return 1 }
        if h < 6.0 { return (6.0 - h) / 1.5 }
        if h > 18.3 { return (h - 18.3) / 1.5 }
        return 0
    }

    public static func windowsLit(_ hour: Double) -> Bool { hour >= 17.0 || hour < 5.6 }
}

/// 138pt living procedural diorama canvas with sky gradient, sun/moon arc, drifting clouds, stars, and skyline.
public struct DioramaSkyView: View {
    public let hour: Double
    public let hijriDay: Int
    public var sunriseHour: Double = 5.75
    public var sunsetHour: Double = 18.3
    public var pixel: Bool = false
    public var skyline: Bool = true
    public var skylineHeight: CGFloat = 0.12

    private struct Star {
        let x: Double
        let y: Double
        let isCross: Bool
        let brightness: Double
    }

    private static let stars: [Star] = [
        Star(x: 0.08, y: 0.16, isCross: false, brightness: 0.8),
        Star(x: 0.16, y: 0.38, isCross: false, brightness: 0.75),
        Star(x: 0.23, y: 0.12, isCross: true,  brightness: 0.95),
        Star(x: 0.32, y: 0.26, isCross: false, brightness: 0.7),
        Star(x: 0.43, y: 0.10, isCross: false, brightness: 0.85),
        Star(x: 0.48, y: 0.34, isCross: true,  brightness: 0.90),
        Star(x: 0.58, y: 0.16, isCross: false, brightness: 0.75),
        Star(x: 0.67, y: 0.30, isCross: false, brightness: 0.8),
        Star(x: 0.74, y: 0.08, isCross: true,  brightness: 0.95),
        Star(x: 0.82, y: 0.24, isCross: false, brightness: 0.8),
        Star(x: 0.90, y: 0.14, isCross: false, brightness: 0.7),
        Star(x: 0.95, y: 0.32, isCross: false, brightness: 0.85),
    ]
    private static let buildings: [Double] = [0.20, 0.30, 0.24, 0.38, 0.22, 0.32, 0.18, 0.28, 0.36, 0.21, 0.30, 0.16]

    public init(
        hour: Double,
        hijriDay: Int,
        sunriseHour: Double = 5.75,
        sunsetHour: Double = 18.3,
        pixel: Bool = false,
        skyline: Bool = true,
        skylineHeight: CGFloat = 0.12
    ) {
        self.hour = hour
        self.hijriDay = hijriDay
        self.sunriseHour = sunriseHour
        self.sunsetHour = sunsetHour
        self.pixel = pixel
        self.skyline = skyline
        self.skylineHeight = skylineHeight
    }

    public var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = pixel ? 3.0 : 0
            func snap(_ v: CGFloat) -> CGFloat { cell > 0 ? (v / cell).rounded() * cell : v }

            if pixel {
                // ── 1. AUTHENTIC 8-BIT STEPPED SKY WITH CHECKERBOARD DITHERING ──
                let bands = DioramaSkyPalette.pixelBands(hour)
                let bandCount = CGFloat(bands.count)
                let bandH = size.height / bandCount

                for i in 0..<bands.count {
                    let y0 = snap(CGFloat(i) * bandH)
                    let y1 = snap(CGFloat(i + 1) * bandH)
                    let rect = CGRect(x: 0, y: y0, width: size.width, height: y1 - y0)
                    ctx.fill(Path(rect), with: .color(bands[i]))

                    // Dither transition to next band
                    if i < bands.count - 1 {
                        let ditherH: CGFloat = 6.0
                        let ditherY = y1 - (ditherH / 2.0)
                        let nextColor = bands[i + 1]
                        var dx: CGFloat = 0
                        while dx < size.width {
                            var dy: CGFloat = 0
                            while dy < ditherH {
                                let px = snap(dx)
                                let py = snap(ditherY + dy)
                                if (Int(px / 3.0) + Int(py / 3.0)) % 2 == 0 {
                                    ctx.fill(Path(CGRect(x: px, y: py, width: 3.0, height: 3.0)), with: .color(nextColor))
                                }
                                dy += 3.0
                            }
                            dx += 3.0
                        }
                    }
                }
            } else {
                // ── 1. MODERN SMOOTH LINEAR GRADIENT ──
                let (top, bottom) = DioramaSkyPalette.colors(hour)
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [top, bottom]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }

            let night = DioramaSkyPalette.nightFactor(hour)
            if night > 0.05 {
                for star in Self.stars {
                    let cx = snap(star.x * size.width)
                    let cy = snap(star.y * size.height * 0.72)
                    let a = night * star.brightness
                    if pixel {
                        // 8-bit stepped pixel stars & diamond crosses
                        if star.isCross {
                            ctx.fill(Path(CGRect(x: cx, y: cy - 3, width: 3, height: 9)), with: .color(.white.opacity(a)))
                            ctx.fill(Path(CGRect(x: cx - 3, y: cy, width: 9, height: 3)), with: .color(.white.opacity(a)))
                            ctx.fill(Path(CGRect(x: cx, y: cy, width: 3, height: 3)), with: .color(Color(red: 1.0, green: 0.95, blue: 0.7).opacity(a)))
                        } else {
                            ctx.fill(Path(CGRect(x: cx, y: cy, width: 3, height: 3)), with: .color(.white.opacity(a)))
                        }
                    } else {
                        if star.isCross {
                            ctx.fill(Path(CGRect(x: cx - 1, y: cy - 1, width: 2, height: 2)), with: .color(.white.opacity(a)))
                            ctx.fill(Path(CGRect(x: cx - 2, y: cy, width: 5, height: 1)), with: .color(.white.opacity(a * 0.75)))
                            ctx.fill(Path(CGRect(x: cx, y: cy - 2, width: 1, height: 5)), with: .color(.white.opacity(a * 0.75)))
                        } else {
                            ctx.fill(Path(CGRect(x: cx, y: cy, width: 1.5, height: 1.5)), with: .color(.white.opacity(a)))
                        }
                    }
                }
            }

            // Dynamic celestial arc: Sunrise -> Sunset (Sun), Sunset -> Next Sunrise (Moon)
            let sunrise = sunriseHour
            let sunset = sunsetHour
            let nextSunrise = sunrise + 24.0
            let horizonY = size.height * (skyline ? 0.78 : 0.95)
            let archH = horizonY * 0.72
            func arcPoint(_ p: Double) -> CGPoint {
                CGPoint(x: size.width * (0.08 + 0.84 * p), y: horizonY - archH * sin(.pi * p))
            }
            let h = hour
            if h >= sunrise && h <= sunset {
                let p = (h - sunrise) / max(0.1, sunset - sunrise)
                let c = arcPoint(p)
                let r = min(size.width, size.height) * 0.08
                let col = (h >= (sunset - 2.8) && h < sunset) ? Color(red: 1.0, green: 0.58, blue: 0.20) : Color(red: 1.0, green: 0.92, blue: 0.45)
                let rimCol = Color(red: 1.0, green: 0.65, blue: 0.15)

                if pixel {
                    // True 8-bit stepped pixel sun
                    let cx = snap(c.x)
                    let cy = snap(c.y)
                    let pr = snap(r)
                    // Outer golden rim
                    ctx.fill(Path(CGRect(x: cx - pr, y: cy - pr * 0.6, width: pr * 2, height: pr * 1.2)), with: .color(rimCol))
                    ctx.fill(Path(CGRect(x: cx - pr * 0.6, y: cy - pr, width: pr * 1.2, height: pr * 2)), with: .color(rimCol))
                    // Inner bright core
                    let ir = pr * 0.7
                    ctx.fill(Path(CGRect(x: cx - ir, y: cy - ir * 0.6, width: ir * 2, height: ir * 1.2)), with: .color(col))
                    ctx.fill(Path(CGRect(x: cx - ir * 0.6, y: cy - ir, width: ir * 1.2, height: ir * 2)), with: .color(col))
                    // 4-directional pixel rays
                    ctx.fill(Path(CGRect(x: cx - 1.5, y: cy - pr - 5, width: 3, height: 4)), with: .color(col.opacity(0.85)))
                    ctx.fill(Path(CGRect(x: cx - 1.5, y: cy + pr + 1, width: 3, height: 4)), with: .color(col.opacity(0.85)))
                    ctx.fill(Path(CGRect(x: cx - pr - 5, y: cy - 1.5, width: 4, height: 3)), with: .color(col.opacity(0.85)))
                    ctx.fill(Path(CGRect(x: cx + pr + 1, y: cy - 1.5, width: 4, height: 3)), with: .color(col.opacity(0.85)))
                } else {
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.8, y: c.y - r * 1.8, width: r * 3.6, height: r * 3.6)), with: .color(col.opacity(0.20)))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(col))
                }
            } else {
                let hh = h < sunrise ? h + 24.0 : h
                let p = max(0, min(1, (hh - sunset) / max(0.1, nextSunrise - sunset)))
                let c = arcPoint(p)
                let r = min(size.width, size.height) * 0.08
                let cx = snap(c.x)
                let cy = snap(c.y)
                let pr = snap(r)

                if pixel {
                    // True 8-bit stepped pixel crescent moon
                    let moonColor = Color(red: 0.98, green: 0.98, blue: 0.92)
                    let skyBands = DioramaSkyPalette.pixelBands(hour)
                    let skyBack = skyBands.first ?? Color(red: 0.05, green: 0.07, blue: 0.16)

                    // Base stepped circle
                    ctx.fill(Path(CGRect(x: cx - pr, y: cy - pr * 0.6, width: pr * 2, height: pr * 1.2)), with: .color(moonColor))
                    ctx.fill(Path(CGRect(x: cx - pr * 0.6, y: cy - pr, width: pr * 1.2, height: pr * 2)), with: .color(moonColor))

                    // Stepped crescent cutout
                    let shift: CGFloat = 4.0
                    ctx.fill(Path(CGRect(x: cx - pr + shift, y: cy - pr * 0.6, width: pr * 2, height: pr * 1.2)), with: .color(skyBack))
                    ctx.fill(Path(CGRect(x: cx - pr * 0.6 + shift, y: cy - pr, width: pr * 1.2, height: pr * 2)), with: .color(skyBack))
                } else {
                    let phaseRatio = Double(max(1, min(30, hijriDay))) / 29.5
                    let illuminated = 0.5 * (1.0 - cos(2.0 * .pi * phaseRatio))
                    let moonRect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                    let moonPath = Path(ellipseIn: moonRect)
                    ctx.fill(moonPath, with: .color(Color(red: 0.96, green: 0.96, blue: 0.92)))

                    if illuminated < 0.92 {
                        ctx.drawLayer { layer in
                            layer.clip(to: moonPath)
                            let cutoutR = r * 1.02
                            let shift = (phaseRatio < 0.5 ? 1.0 : -1.0) * Double(r) * (0.28 + illuminated * 1.9)
                            let cutoutRect = CGRect(x: c.x - cutoutR + CGFloat(shift), y: c.y - cutoutR, width: cutoutR * 2, height: cutoutR * 2)
                            let (top, _) = DioramaSkyPalette.colors(hour)
                            layer.fill(Path(ellipseIn: cutoutRect), with: .color(top))
                        }
                    }
                }
            }

            // Clouds (drift with the hour)
            let cloudColor = night > 0.3
                ? Color(red: 0.08, green: 0.07, blue: 0.16).opacity(0.40)
                : Color.white.opacity(0.35 * (1.0 - night))

            let clouds: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0.44, 0.22, 48.0, 10.0),
                (0.68, 0.30, 56.0, 11.0),
            ]
            for (baseX, baseY, cw, ch) in clouds {
                let cx = (baseX * size.width + CGFloat(hour) * 3).truncatingRemainder(dividingBy: size.width + 80) - 40
                let cy = baseY * size.height
                if pixel {
                    // 8-bit stepped blocky pixel cloud
                    let px = snap(cx)
                    let py = snap(cy)
                    let pw = snap(cw)
                    let ph = snap(ch)
                    ctx.fill(Path(CGRect(x: px + 4, y: py, width: pw - 8, height: ph)), with: .color(cloudColor))
                    ctx.fill(Path(CGRect(x: px, y: py + 3, width: pw, height: ph - 3)), with: .color(cloudColor))
                } else {
                    let rect = CGRect(x: snap(cx), y: snap(cy), width: snap(cw), height: snap(ch))
                    ctx.fill(Path(roundedRect: rect, cornerRadius: ch / 2), with: .color(cloudColor))
                }
            }

            // Skyline / Mosque Architecture
            if skyline {
                let baseSkylineY = size.height * 0.98
                let lit = DioramaSkyPalette.windowsLit(hour)
                let silhouetteColor = Color(red: 0.05, green: 0.04, blue: 0.10)
                let windowGold = Color(red: 1.0, green: 0.88, blue: 0.38)

                if pixel {
                    // ── AUTHENTIC 8-BIT PIXEL MOSQUE SILHOUETTE ──
                    // Left Minaret
                    let m1X = snap(size.width * 0.12)
                    let mH: CGFloat = snap(size.height * 0.34)
                    ctx.fill(Path(CGRect(x: m1X - 5, y: baseSkylineY - mH, width: 10, height: mH)), with: .color(silhouetteColor))
                    // Minaret Balcony
                    ctx.fill(Path(CGRect(x: m1X - 7, y: baseSkylineY - mH * 0.72, width: 14, height: 3)), with: .color(silhouetteColor))
                    // Minaret Spire
                    ctx.fill(Path(CGRect(x: m1X - 2.5, y: baseSkylineY - mH - 7, width: 5, height: 8)), with: .color(silhouetteColor))
                    ctx.fill(Path(CGRect(x: m1X - 1, y: baseSkylineY - mH - 10, width: 2, height: 4)), with: .color(silhouetteColor))

                    // Right Minaret
                    let m2X = snap(size.width * 0.88)
                    ctx.fill(Path(CGRect(x: m2X - 5, y: baseSkylineY - mH, width: 10, height: mH)), with: .color(silhouetteColor))
                    ctx.fill(Path(CGRect(x: m2X - 7, y: baseSkylineY - mH * 0.72, width: 14, height: 3)), with: .color(silhouetteColor))
                    ctx.fill(Path(CGRect(x: m2X - 2.5, y: baseSkylineY - mH - 7, width: 5, height: 8)), with: .color(silhouetteColor))
                    ctx.fill(Path(CGRect(x: m2X - 1, y: baseSkylineY - mH - 10, width: 2, height: 4)), with: .color(silhouetteColor))

                    // Central Grand Mosque Dome (Stepped 8-bit hemisphere)
                    let domeCX = snap(size.width * 0.50)
                    let domeBaseH = snap(size.height * 0.14)
                    let domeWallW = snap(min(size.width * 0.32, 110))
                    // Base building wall
                    ctx.fill(Path(CGRect(x: domeCX - domeWallW / 2, y: baseSkylineY - domeBaseH, width: domeWallW, height: domeBaseH)), with: .color(silhouetteColor))

                    // Stepped Dome Curves
                    let steps: [(w: CGFloat, h: CGFloat)] = [
                        (domeWallW * 0.85, 5),
                        (domeWallW * 0.72, 6),
                        (domeWallW * 0.56, 6),
                        (domeWallW * 0.38, 5),
                        (domeWallW * 0.20, 4),
                        (domeWallW * 0.08, 4)
                    ]
                    var currY = baseSkylineY - domeBaseH
                    for step in steps {
                        currY -= step.h
                        ctx.fill(Path(CGRect(x: domeCX - step.w / 2, y: currY, width: step.w, height: step.h)), with: .color(silhouetteColor))
                    }
                    // Dome Finial Crescent
                    ctx.fill(Path(CGRect(x: domeCX - 1.5, y: currY - 6, width: 3, height: 6)), with: .color(silhouetteColor))
                    ctx.fill(Path(CGRect(x: domeCX - 3, y: currY - 8, width: 4, height: 2)), with: .color(silhouetteColor))

                    // Lit Golden Pixel Windows inside Mosque
                    if lit {
                        for offX in [-20.0, 0.0, 20.0] as [CGFloat] {
                            let wx = snap(domeCX + offX - 2.5)
                            let wy = snap(baseSkylineY - domeBaseH * 0.65)
                            ctx.fill(Path(CGRect(x: wx, y: wy, width: 5, height: 7)), with: .color(windowGold.opacity(0.9)))
                            ctx.fill(Path(CGRect(x: wx + 1, y: wy - 2, width: 3, height: 2)), with: .color(windowGold.opacity(0.9)))
                        }
                    }

                    // Connecting Side Walls
                    let wall1W = m1X - 5
                    ctx.fill(Path(CGRect(x: 0, y: baseSkylineY - 10, width: wall1W, height: 10)), with: .color(silhouetteColor))
                    let wall2W = size.width - (m2X + 5)
                    ctx.fill(Path(CGRect(x: m2X + 5, y: baseSkylineY - 10, width: wall2W, height: 10)), with: .color(silhouetteColor))
                } else {
                    // Modern Clean Skyline + Silhouette
                    let n = Self.buildings.count
                    let w = size.width / CGFloat(n)
                    for (i, bh) in Self.buildings.enumerated() {
                        let bHeight = snap(size.height * skylineHeight * CGFloat(bh) / 0.38)
                        let rect = CGRect(x: snap(CGFloat(i) * w), y: baseSkylineY - bHeight, width: snap(w) + 0.5, height: bHeight + size.height * 0.15)
                        ctx.fill(Path(rect), with: .color(Color(red: 0.07, green: 0.06, blue: 0.13)))
                        if lit {
                            var wy = rect.minY + 4
                            while wy < baseSkylineY - 4 {
                                let wx = rect.minX + w * 0.32
                                ctx.fill(Path(CGRect(x: snap(wx), y: snap(wy), width: 2.2, height: 2.2)),
                                         with: .color(Color(red: 1.0, green: 0.85, blue: 0.45).opacity(0.85)))
                                wy += 6.5
                            }
                        }
                    }
                }
            }
        }
    }
}
