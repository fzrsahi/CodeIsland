import XCTest
@testable import CodeIsland

final class FloatingLyricPresetTests: XCTestCase {

    func testAllFloatingLyricPresetsDefined() {
        let expectedCases: [FloatingLyricPreset] = [
            .pureText,
            .capsule,
            .frostedGlass,
            .neonHud,
            .seamlessGlass,
            .retroPixel,
            .liquidAurora,
            .minimalBraun,
            .tapeReel,
            .vinylGroove,
            .fluidKaraoke,
            .connectedChin
        ]

        XCTAssertEqual(FloatingLyricPreset.allCases.count, 12)
        for preset in expectedCases {
            XCTAssertTrue(FloatingLyricPreset.allCases.contains(preset))
            XCTAssertFalse(preset.title.isEmpty)
            XCTAssertFalse(preset.shortLabel.isEmpty)
            XCTAssertFalse(preset.description.isEmpty)
        }
    }

    func testSeamlessGlassPresetProperties() {
        let preset = FloatingLyricPreset.seamlessGlass
        XCTAssertEqual(preset.rawValue, "seamlessGlass")
        XCTAssertEqual(preset.shortLabel, "SEAMLESS")
        XCTAssertTrue(preset.title.contains("Seamless Glass"))
    }

    func testPresetRawValuesRoundTrip() {
        for preset in FloatingLyricPreset.allCases {
            let roundTrip = FloatingLyricPreset(rawValue: preset.rawValue)
            XCTAssertEqual(roundTrip, preset)
        }
    }

    func testAllFloatingLyricIconStylesDefined() {
        let expectedStyles: [FloatingLyricIconStyle] = [
            .spinningVinyl,
            .albumTurntable,
            .dancingWave,
            .pulsingNote,
            .retroCassette,
            .studioMic,
            .hapticBubble,
            .none
        ]

        XCTAssertEqual(FloatingLyricIconStyle.allCases.count, 8)
        for style in expectedStyles {
            XCTAssertTrue(FloatingLyricIconStyle.allCases.contains(style))
            XCTAssertFalse(style.title.isEmpty)
            XCTAssertFalse(style.description.isEmpty)
            let roundTrip = FloatingLyricIconStyle(rawValue: style.rawValue)
            XCTAssertEqual(roundTrip, style)
        }
    }

    func testAllFloatingLyricFontDesignsDefined() {
        let expectedDesigns: [FloatingLyricFontDesign] = [
            .rounded,
            .monospaced,
            .system,
            .serif,
            .pixel
        ]

        XCTAssertEqual(FloatingLyricFontDesign.allCases.count, 5)
        for design in expectedDesigns {
            XCTAssertTrue(FloatingLyricFontDesign.allCases.contains(design))
            XCTAssertFalse(design.title.isEmpty)
            let roundTrip = FloatingLyricFontDesign(rawValue: design.rawValue)
            XCTAssertEqual(roundTrip, design)
        }
    }
}
