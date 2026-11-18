import SwiftUI
import AppKit

// MARK: - 1. Pixel Cyber Cat (Neko)

struct NekoMascotView: View {
    let status: MascotAgentStatus
    var size: CGFloat = 27

    init(status: MascotAgentStatus, size: CGFloat = 27) {
        self.status = status
        self.size = size
    }

    var body: some View {
        MascotTimeline(interval: 0.12) { t in
            Canvas { context, sz in
                let scale = sz.width / 16.0
                let isWorking = (status == .processing || status == .running)
                let isAlert = (status == .waitingApproval || status == .waitingQuestion)

                let bounce = isWorking ? sin(t * 12.0) * 1.5 : 0.0

                func drawPixel(x: Int, y: Double, color: Color) {
                    let rect = CGRect(x: Double(x) * scale, y: (y + bounce) * scale, width: scale, height: scale)
                    context.fill(Path(rect), with: .color(color))
                }

                // Cat Colors
                let catBody = Color(red: 0.95, green: 0.95, blue: 0.98) // White Cyber Neko
                let innerEar = Color(red: 1.0, green: 0.45, blue: 0.70)
                let eyeColor = isAlert ? Color(red: 1.0, green: 0.16, blue: 0.53) : Color(red: 0.0, green: 0.90, blue: 0.46)
                let collarColor = Color(red: 1.0, green: 0.85, blue: 0.0)

                // Ears
                drawPixel(x: 3, y: 3, color: catBody)
                drawPixel(x: 4, y: 3, color: innerEar)
                drawPixel(x: 11, y: 3, color: innerEar)
                drawPixel(x: 12, y: 3, color: catBody)

                drawPixel(x: 2, y: 4, color: catBody)
                drawPixel(x: 3, y: 4, color: innerEar)
                drawPixel(x: 12, y: 4, color: innerEar)
                drawPixel(x: 13, y: 4, color: catBody)

                // Head (Rows 5..9)
                for x in 3...12 {
                    drawPixel(x: x, y: 5, color: catBody)
                    drawPixel(x: x, y: 6, color: catBody)
                    drawPixel(x: x, y: 7, color: catBody)
                    drawPixel(x: x, y: 8, color: catBody)
                }

                // Eyes (Row 6)
                if status == .idle {
                    // Closed sleepy eyes (horizontal lines)
                    drawPixel(x: 5, y: 6, color: Color.black)
                    drawPixel(x: 6, y: 6, color: Color.black)
                    drawPixel(x: 9, y: 6, color: Color.black)
                    drawPixel(x: 10, y: 6, color: Color.black)
                } else {
                    // Open glowing eyes
                    drawPixel(x: 5, y: 6, color: eyeColor)
                    drawPixel(x: 6, y: 6, color: Color.black)
                    drawPixel(x: 9, y: 6, color: Color.black)
                    drawPixel(x: 10, y: 6, color: eyeColor)
                }

                // Nose / Whiskers (Row 7 & 8)
                drawPixel(x: 7, y: 7, color: innerEar)
                drawPixel(x: 8, y: 7, color: innerEar)
                drawPixel(x: 1, y: 7, color: catBody)
                drawPixel(x: 14, y: 7, color: catBody)

                // Collar (Row 9)
                for x in 4...11 {
                    drawPixel(x: x, y: 9, color: collarColor)
                }
                // Bell
                drawPixel(x: 7, y: 10, color: Color.orange)
                drawPixel(x: 8, y: 10, color: Color.orange)

                // Body (Rows 10..13)
                for x in 4...11 {
                    drawPixel(x: x, y: 11, color: catBody)
                    drawPixel(x: x, y: 12, color: catBody)
                }

                // Paws (Row 13)
                drawPixel(x: 4, y: 13, color: Color(white: 0.85))
                drawPixel(x: 5, y: 13, color: Color(white: 0.85))
                drawPixel(x: 10, y: 13, color: Color(white: 0.85))
                drawPixel(x: 11, y: 13, color: Color(white: 0.85))

                // Tail (animated swing)
                let tailX = 13 + (isWorking ? Int(sin(t * 10.0) * 1.5) : 0)
                drawPixel(x: tailX, y: 10, color: catBody)
                drawPixel(x: tailX + 1, y: 9, color: catBody)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 2. Cyber Mecha / Titan

struct MechaMascotView: View {
    let status: MascotAgentStatus
    var size: CGFloat = 27

    init(status: MascotAgentStatus, size: CGFloat = 27) {
        self.status = status
        self.size = size
    }

    var body: some View {
        MascotTimeline(interval: 0.1) { t in
            Canvas { context, sz in
                let scale = sz.width / 16.0
                let isWorking = (status == .processing || status == .running)
                let isAlert = (status == .waitingApproval || status == .waitingQuestion)

                let armor = Color(red: 0.22, green: 0.26, blue: 0.35)
                let plating = Color(red: 0.38, green: 0.44, blue: 0.58)
                let visor = isAlert ? Color(red: 1.0, green: 0.16, blue: 0.53) : Color(red: 0.0, green: 0.96, blue: 0.83)
                let coreEnergy = Color(red: 0.0, green: 0.90, blue: 0.46)

                func p(_ x: Int, _ y: Int, _ c: Color) {
                    let rect = CGRect(x: Double(x) * scale, y: Double(y) * scale, width: scale, height: scale)
                    context.fill(Path(rect), with: .color(c))
                }

                // Antenna (Row 1..3)
                let antennaGlow = isWorking && sin(t * 15.0) > 0 ? Color.white : visor
                p(7, 1, antennaGlow)
                p(8, 1, antennaGlow)
                p(7, 2, armor)
                p(8, 2, armor)

                // Head Helmet (Rows 3..8)
                for x in 3...12 {
                    p(x, 3, armor)
                    p(x, 4, plating)
                }

                // Visor Eye Strip (Row 5 & 6)
                for x in 4...11 {
                    p(x, 5, visor)
                    p(x, 6, status == .idle ? armor : visor)
                }

                // Mouthguard (Rows 7..8)
                for x in 5...10 {
                    p(x, 7, plating)
                    p(x, 8, armor)
                }
                // Air Vents
                p(6, 7, Color.black)
                p(9, 7, Color.black)

                // Torso & Core Reactor (Rows 9..13)
                for x in 4...11 {
                    p(x, 9, plating)
                    p(x, 10, armor)
                    p(x, 11, armor)
                }

                // Chest Arc Reactor (glows)
                let corePulse = isWorking ? Color.white : coreEnergy
                p(7, 10, corePulse)
                p(8, 10, corePulse)

                // Shoulder Pauldrons & Arms (Rows 9..12)
                p(2, 9, plating); p(3, 9, plating)
                p(12, 9, plating); p(13, 9, plating)
                p(2, 10, armor); p(13, 10, armor)

                // Legs / Thrusters (Row 13..14)
                p(5, 12, plating); p(6, 12, plating)
                p(9, 12, plating); p(10, 12, plating)
                p(5, 13, armor); p(6, 13, armor)
                p(9, 13, armor); p(10, 13, armor)

                // Thruster exhaust flame when running
                if isWorking {
                    let flame = sin(t * 20.0) > 0 ? Color.cyan : Color.blue
                    p(5, 14, flame); p(10, 14, flame)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 3. 8-Bit Cyber Ghost

struct GhostMascotView: View {
    let status: MascotAgentStatus
    var size: CGFloat = 27

    init(status: MascotAgentStatus, size: CGFloat = 27) {
        self.status = status
        self.size = size
    }

    var body: some View {
        MascotTimeline(interval: 0.1) { t in
            Canvas { context, sz in
                let scale = sz.width / 16.0
                let isWorking = (status == .processing || status == .running)
                let isAlert = (status == .waitingApproval || status == .waitingQuestion)

                // Floating sine wave animation
                let floatY = sin(t * 5.0) * 1.5

                let ghostColor = isAlert ? Color(red: 1.0, green: 0.3, blue: 0.3)
                    : (isWorking ? Color(red: 0.2, green: 0.85, blue: 1.0) : Color(red: 0.85, green: 0.85, blue: 0.98))
                let eyeWhite = Color.white
                let pupil = isAlert ? Color.red : Color(red: 0.05, green: 0.1, blue: 0.4)

                func p(_ x: Int, _ y: Double) {
                    let rect = CGRect(x: Double(x) * scale, y: (y + floatY) * scale, width: scale, height: scale)
                    context.fill(Path(rect), with: .color(ghostColor))
                }
                func c(_ x: Int, _ y: Double, _ color: Color) {
                    let rect = CGRect(x: Double(x) * scale, y: (y + floatY) * scale, width: scale, height: scale)
                    context.fill(Path(rect), with: .color(color))
                }

                // Head curve (Row 3)
                for x in 5...10 { p(x, 3) }
                // Row 4
                for x in 3...12 { p(x, 4) }
                // Body (Rows 5..11)
                for y in 5...11 {
                    for x in 2...13 { p(x, Double(y)) }
                }

                // Eyes (Rows 6 & 7)
                // Eye white
                c(4, 6, eyeWhite); c(5, 6, eyeWhite)
                c(4, 7, eyeWhite); c(5, 7, eyeWhite)

                c(9, 6, eyeWhite); c(10, 6, eyeWhite)
                c(9, 7, eyeWhite); c(10, 7, eyeWhite)

                // Pupils look direction
                let pupilOffset = isWorking ? (sin(t * 8.0) > 0 ? 1 : 0) : 0
                c(4 + pupilOffset, 6, pupil)
                c(9 + pupilOffset, 6, pupil)

                // Ruffled Tentacle Skirt (Rows 12 & 13)
                let step = Int(t * 6.0) % 2
                if step == 0 {
                    p(2, 12); p(3, 12); p(6, 12); p(7, 12); p(8, 12); p(9, 12); p(12, 12); p(13, 12)
                    p(2, 13); p(7, 13); p(8, 13); p(13, 13)
                } else {
                    p(4, 12); p(5, 12); p(7, 12); p(8, 12); p(10, 12); p(11, 12)
                    p(4, 13); p(5, 13); p(10, 13); p(11, 13)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
