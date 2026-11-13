import Foundation
import Observation

/// The values the collapsed bar actually shows.
///
/// The panel root and both wings used to observe five singletons directly, so
/// every published property on any of them — a track position four times a
/// second, a CPU sample, a workspace refresh — re-rendered the whole bar even
/// when nothing visible had changed. This is the short list of values the bar
/// reads; the managers write to it, and a write that does not change the value
/// does not notify anyone.
@Observable
final class IslandSignals {
    static let shared = IslandSignals()

    // Music
    private(set) var isPlaying = false
    private(set) var showToast = false
    private(set) var hasTitle = false
    private(set) var hasLyrics = false

    // Session / panel
    private(set) var tooltipText = ""
    private(set) var isDetailExpanded = false

    // Banners and HUDs
    private(set) var showChargingBanner = false
    private(set) var batteryLevel = 100
    private(set) var showMiniPeekBanner = false
    private(set) var isVolumeHUDVisible = false

    // Prayer
    private(set) var isPrayerPrioritized = false

    // Sound
    private(set) var inQuietHours = false

    init() {}

    // MARK: - Writes
    //
    // Each setter compares before assigning: with `@Observable`, an assignment
    // is a notification whether or not the value moved.

    func setMusic(isPlaying: Bool, showToast: Bool, hasTitle: Bool, hasLyrics: Bool) {
        if self.isPlaying != isPlaying { self.isPlaying = isPlaying }
        if self.showToast != showToast { self.showToast = showToast }
        if self.hasTitle != hasTitle { self.hasTitle = hasTitle }
        if self.hasLyrics != hasLyrics { self.hasLyrics = hasLyrics }
    }

    func setTooltip(_ text: String) {
        if tooltipText != text { tooltipText = text }
    }

    func setDetailExpanded(_ expanded: Bool) {
        if isDetailExpanded != expanded { isDetailExpanded = expanded }
    }

    func setChargingBanner(visible: Bool, batteryLevel: Int) {
        if showChargingBanner != visible { showChargingBanner = visible }
        if self.batteryLevel != batteryLevel { self.batteryLevel = batteryLevel }
    }

    func setMiniPeekBanner(_ visible: Bool) {
        if showMiniPeekBanner != visible { showMiniPeekBanner = visible }
    }

    func setVolumeHUDVisible(_ visible: Bool) {
        if isVolumeHUDVisible != visible { isVolumeHUDVisible = visible }
    }

    func setPrayerPrioritized(_ prioritized: Bool) {
        if isPrayerPrioritized != prioritized { isPrayerPrioritized = prioritized }
    }

    func setInQuietHours(_ quiet: Bool) {
        if inQuietHours != quiet { inQuietHours = quiet }
    }
}
