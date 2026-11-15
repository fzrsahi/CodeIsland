import XCTest
@testable import CodeIsland

/// Ticket 04: visual musik collapsed digerakkan Core Animation dengan
/// parameter varian B dari prototype. Spec "tidak di-test otomatis" untuk
/// tampilan visualnya (dinilai manusia lewat prototype); yang di-test di sini
/// adalah jaring pengaman tiket: rumus ter-clamp, loop 6 dtk mulus, ukuran
/// view tetap, dan frame diam saat kelas tidak aktif.
final class CAMusicVisualsTests: XCTestCase {
    // MARK: - Rumus varian B

    func testModernLevelIsClampedToQuarterThroughFull() {
        for i in 0..<5 {
            var t = 0.0
            while t <= CAMusicCurves.period {
                let v = CAMusicCurves.modernLevel(at: t, bar: i)
                XCTAssertGreaterThanOrEqual(v, 0.25, "t=\(t) bar=\(i)")
                XCTAssertLessThanOrEqual(v, 1.0, "t=\(t) bar=\(i)")
                t += 0.02
            }
        }
    }

    func testRetroLevelIsClamped() {
        for i in 0..<5 {
            var t = 0.0
            while t <= CAMusicCurves.period {
                let v = CAMusicCurves.retroLevel(at: t, bar: i)
                XCTAssertGreaterThanOrEqual(v, 0.15, "t=\(t) bar=\(i)")
                XCTAssertLessThanOrEqual(v, 1.0, "t=\(t) bar=\(i)")
                t += 0.02
            }
        }
    }

    /// Frekuensi prototype dibulatkan ke 3 desimal, jadi 6 dtk bukan
    /// kelipatan siklus yang persis — tapi simpangannya ≤ 0,002 pada level
    /// (tak terlihat; sama seperti prototype yang sudah terukur). Test ini
    /// mengunci bahwa loop-nya tetap nyaris mulus, bukan patah besar.
    func testSixSecondLoopIsSeamless() {
        for i in 0..<5 {
            XCTAssertEqual(CAMusicCurves.modernLevel(at: 0, bar: i),
                           CAMusicCurves.modernLevel(at: CAMusicCurves.period, bar: i),
                           accuracy: 0.005, "modern bar=\(i)")
            XCTAssertEqual(CAMusicCurves.retroLevel(at: 0, bar: i),
                           CAMusicCurves.retroLevel(at: CAMusicCurves.period, bar: i),
                           accuracy: 0.005, "retro bar=\(i)")
        }
    }

    func testRetroSegmentsAreFourDiscreteLevels() {
        XCTAssertEqual(CAMusicCurves.retroActiveSegments(level: 0.15), 1)
        XCTAssertEqual(CAMusicCurves.retroActiveSegments(level: 0.25), 1)
        XCTAssertEqual(CAMusicCurves.retroActiveSegments(level: 0.5), 2)
        XCTAssertEqual(CAMusicCurves.retroActiveSegments(level: 0.8), 3)
        XCTAssertEqual(CAMusicCurves.retroActiveSegments(level: 1.0), 4)
    }

    func testSamplingIncludesBothEndsAt25fps() {
        let s = CAMusicCurves.samples(duration: CAMusicCurves.period) { $0 }
        XCTAssertEqual(s.count, Int(CAMusicCurves.period * CAMusicCurves.fps) + 1)
        XCTAssertEqual(s.first ?? -1, 0, accuracy: 1e-12)
        XCTAssertEqual(s.last ?? -1, CAMusicCurves.period, accuracy: 1e-12)
    }

    // MARK: - Ukuran view tetap (pengukuran wing tidak berubah)

    func testModernSizeMatchesSwiftUIHStack() {
        // HStack(spacing 1.6), tinggi maxHeight.
        let size = CAModernSpectrumView.fixedSize(barCount: 3, barWidth: 2.0, maxHeight: 11.0)
        XCTAssertEqual(size.width, 3 * 2.0 + 2 * 1.6, accuracy: 1e-9)
        XCTAssertEqual(size.height, 11.0, accuracy: 1e-9)
    }

    func testRetroSizeMatchesSwiftUIHStack() {
        // HStack(spacing 1.5), tinggi 4 segmen + 3 spacing.
        let size = CARetroSpectrumView.fixedSize(barCount: 4, barWidth: 2.0,
                                                 segmentHeight: 1.6, segmentSpacing: 0.8)
        XCTAssertEqual(size.width, 4 * 2.0 + 3 * 1.5, accuracy: 1e-9)
        XCTAssertEqual(size.height, 4 * 1.6 + 3 * 0.8, accuracy: 1e-9)
    }

    /// Hover mengubah jumlah bar Retro 4 → 3 dan lebarnya tetap terukur.
    func testRetroHoverBarCountStillChangesWidth() {
        let wide = CARetroSpectrumView.fixedSize(barCount: 4, barWidth: 2.0,
                                                 segmentHeight: 1.6, segmentSpacing: 0.8)
        let narrow = CARetroSpectrumView.fixedSize(barCount: 3, barWidth: 2.0,
                                                   segmentHeight: 1.6, segmentSpacing: 0.8)
        XCTAssertGreaterThan(wide.width, narrow.width)
        XCTAssertEqual(narrow.width, 3 * 2.0 + 2 * 1.5, accuracy: 1e-9)
    }

    // MARK: - Glow: periode dan state diam

    func testGlowPeriodsMatchTodayFormulas() {
        // Aura sin(3.5t) → 2π/3.5; breath sin(2t) → π.
        let aura = CAMusicGlowView(kind: .aura, mascotSize: 27, animating: true)
        let breath = CAMusicGlowView(kind: .breath, mascotSize: 27, animating: true)
        XCTAssertEqual(aura.period, 2 * .pi / 3.5, accuracy: 1e-12)
        XCTAssertEqual(breath.period, .pi, accuracy: 1e-12)
    }

    func testGlowMidStateHasTodayRadii() {
        let aura = CAMusicGlowView(kind: .aura, mascotSize: 27, animating: false)
        let breath = CAMusicGlowView(kind: .breath, mascotSize: 27, animating: false)
        // endRadius = … + v·3 (aura) / + v·2 (breath), side = mascot+8 / +4.
        // state(0.5) dipakai sebagai still frame saat kelas tidak aktif.
        let rAura = 27 * 0.6 + 0.5 * 3
        let rBreath = 27 * 0.55 + 0.5 * 2
        XCTAssertEqual(aura.state(0.5).endPoint.x, 0.5 + rAura / (27 + 8), accuracy: 1e-9)
        XCTAssertEqual(breath.state(0.5).endPoint.x, 0.5 + rBreath / (27 + 4), accuracy: 1e-9)
    }
}
