import SwiftUI
import XCTest
@testable import Morrow

@MainActor
final class NotificationRedesignTests: XCTestCase {
    func testPowerBannerStatesProduceExpectedCopy() {
        let magSafe = PowerBannerState.charging(kind: .magSafe, watts: 140, timeToFullMinutes: 28)
        XCTAssertEqual(magSafe.title, "MagSafe Charging")
        XCTAssertEqual(magSafe.subtitle, "140W MagSafe · ~28m left")

        let usbC = PowerBannerState.charging(kind: .usbC, watts: 67, timeToFullMinutes: 41)
        XCTAssertEqual(usbC.title, "USB-C Charging")
        XCTAssertEqual(usbC.subtitle, "67W USB-C · ~41m left")

        let onHold = PowerBannerState.chargingOnHold(kind: .usbC, watts: 20)
        XCTAssertEqual(onHold.title, "Charging On Hold")
        XCTAssertEqual(onHold.subtitle, "Optimized Charging · 20W USB-C")

        let full = PowerBannerState.fullyCharged(kind: .magSafe)
        XCTAssertEqual(full.title, "Fully Charged")
        XCTAssertEqual(full.subtitle, "MagSafe Connected")

        let low = PowerBannerState.lowBattery
        XCTAssertEqual(low.title, "Low Battery")
        XCTAssertEqual(low.subtitle, "Connect power adapter")
    }

    func testChargingBannerRendersModernAndPixelAcrossStates() {
        let defaults = UserDefaults.standard
        let originalTheme = defaults.string(forKey: SettingsKey.islandUITheme)
        defer {
            if let originalTheme {
                defaults.set(originalTheme, forKey: SettingsKey.islandUITheme)
            } else {
                defaults.removeObject(forKey: SettingsKey.islandUITheme)
            }
        }

        let states: [(PowerBannerState, Int)] = [
            (.charging(kind: .magSafe, watts: 140, timeToFullMinutes: 28), 70),
            (.charging(kind: .usbC, watts: 67, timeToFullMinutes: 41), 64),
            (.chargingOnHold(kind: .usbC, watts: 20), 90),
            (.fullyCharged(kind: .magSafe), 100),
            (.lowBattery, 15)
        ]

        for theme in [IslandUITheme.modern, IslandUITheme.pixel] {
            defaults.set(theme.rawValue, forKey: SettingsKey.islandUITheme)
            for (state, pct) in states {
                let view = MagSafeChargingBanner(batteryLevel: pct, displayMode: .notch, powerState: state)
                    .frame(width: 440)
                    .background(Color.black)
                let host = NSHostingView(rootView: view)
                host.setFrameSize(NSSize(width: 440, height: 80))
                host.layoutSubtreeIfNeeded()
                XCTAssertGreaterThan(host.fittingSize.height, 40, "Charging banner should have non-zero height for \(theme.rawValue)")
            }
        }
    }

    func testPrayerMiniPeekAndExpandedCardRenderInModernAndPixel() {
        let defaults = UserDefaults.standard
        let originalTheme = defaults.string(forKey: SettingsKey.islandUITheme)
        let originalMode = defaults.string(forKey: SettingsKey.prayerCardDisplayMode)
        defer {
            if let originalTheme { defaults.set(originalTheme, forKey: SettingsKey.islandUITheme) }
            else { defaults.removeObject(forKey: SettingsKey.islandUITheme) }
            if let originalMode { defaults.set(originalMode, forKey: SettingsKey.prayerCardDisplayMode) }
            else { defaults.removeObject(forKey: SettingsKey.prayerCardDisplayMode) }
        }

        defaults.set(PrayerCardDisplayMode.compact.rawValue, forKey: SettingsKey.prayerCardDisplayMode)

        for theme in [IslandUITheme.modern, IslandUITheme.pixel] {
            defaults.set(theme.rawValue, forKey: SettingsKey.islandUITheme)

            let banner = PrayerMiniPeekBannerView(manager: PrayerTimeManager.shared, onOpenFull: {})
                .frame(width: 420)
                .background(Color.black)
            let bannerHost = NSHostingView(rootView: banner)
            bannerHost.setFrameSize(NSSize(width: 420, height: 80))
            bannerHost.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(bannerHost.fittingSize.height, 40)

            let card = PrayerExpandedCardView(manager: PrayerTimeManager.shared)
                .frame(width: 593)
                .background(Color.black)
            let cardHost = NSHostingView(rootView: card)
            cardHost.setFrameSize(NSSize(width: 593, height: 180))
            cardHost.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(cardHost.fittingSize.height, 120)
        }
    }
}
