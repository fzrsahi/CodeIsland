import SwiftUI
import CodeIslandCore
import AppKit

// MARK: - Guaranteed 60fps Dancing Audio Spectrum (TimelineView)

struct CyberAudioSpectrumView: View {
    var barCount: Int = 4
    var isPlaying: Bool = true
    var barWidth: CGFloat = 2.6
    var segmentHeight: CGFloat = 1.8
    var segmentSpacing: CGFloat = 1.0

    private func segmentColor(level: Int, isActive: Bool) -> Color {
        guard isActive else {
            return Color(red: 0.12, green: 0.14, blue: 0.18)
        }
        switch level {
        case 0, 1:
            return Color(red: 0.0, green: 0.96, blue: 0.83) // Electric Cyan
        case 2:
            return Color(red: 0.96, green: 0.62, blue: 0.04) // Neon Amber
        default:
            return Color(red: 1.0, green: 0.16, blue: 0.53) // Peak Magenta
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.04)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<barCount, id: \.self) { barIndex in
                    let normalized: Double = {
                        guard isPlaying else { return 0.2 }
                        let factor = Double(barIndex)
                        let b1 = sin(time * 8.0 + factor * 1.5) * 0.4
                        let b2 = cos(time * 13.0 + factor * 2.2) * 0.3
                        let b3 = sin(time * 4.5) * 0.15
                        return max(0.15, min(1.0, 0.45 + b1 + b2 + b3))
                    }()
                    let activeCount = isPlaying ? Int((normalized * 4.0).rounded()) : 1

                    VStack(spacing: segmentSpacing) {
                        ForEach((0..<4).reversed(), id: \.self) { step in
                            Rectangle()
                                .fill(segmentColor(level: step, isActive: step < activeCount))
                                .frame(width: barWidth, height: segmentHeight)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Retro Disco Equalizer Visualizer

struct CyberDiscoVisualizer: View {
    var isPlaying: Bool = true
    var barCount: Int = 6
    var maxHeight: CGFloat = 18

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.04)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2.0) {
                ForEach(0..<barCount, id: \.self) { i in
                    let factor = Double(i) * 0.9
                    let wave = isPlaying
                        ? max(0.12, min(1.0, 0.5 + sin(time * 7.0 + factor) * 0.35 + cos(time * 12.0 + factor * 1.7) * 0.25))
                        : 0.15
                    let barH = max(3, maxHeight * CGFloat(wave))

                    VStack(spacing: 1.2) {
                        Rectangle()
                            .fill(Color(red: 1.0, green: 0.16, blue: 0.53))
                            .frame(width: 2.5, height: 1.5)
                            .opacity(isPlaying && wave > 0.6 ? 1 : 0.2)

                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.0, green: 0.96, blue: 0.83),
                                        Color(red: 0.96, green: 0.62, blue: 0.04),
                                        Color(red: 1.0, green: 0.16, blue: 0.53)
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 2.5, height: barH)
                    }
                }
            }
            .frame(height: maxHeight + 4, alignment: .bottom)
        }
    }
}

// MARK: - Compact Wing Music View (Ultra-Compact for Small Notch)

struct CyberMusicWingView: View {
    @ObservedObject var nowPlaying: NowPlayingManager

    init(nowPlaying: NowPlayingManager) {
        self.nowPlaying = nowPlaying
    }

    var body: some View {
        HStack(spacing: 3) {
            // Mini Album Art
            if let art = nowPlaying.artworkImage {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 13, height: 13)
                    .clipShape(RoundedRectangle(cornerRadius: 2.5))
                    .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color(white: 0.3), lineWidth: 0.5))
            } else {
                Circle()
                    .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.8), lineWidth: 0.8))
            }

            // Real-Time Dancing Equalizer
            CyberAudioSpectrumView(barCount: 4, isPlaying: nowPlaying.isPlaying, barWidth: 2.0, segmentHeight: 1.6, segmentSpacing: 0.8)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1.5)
        .background(
            RoundedRectangle(cornerRadius: 3.5)
                .fill(Color(red: 0.07, green: 0.08, blue: 0.11))
                .overlay(RoundedRectangle(cornerRadius: 3.5).stroke(Color(red: 0.16, green: 0.19, blue: 0.25), lineWidth: 0.75))
        )
    }
}

// MARK: - Mini Peek Banner (Buka Tipis-Tipis saat Ganti Lagu)

struct CyberMusicMiniPeekBanner: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    var onOpenFull: () -> Void

    var body: some View {
        Button(action: onOpenFull) {
            HStack(spacing: 8) {
                // Animated Cover Art
                if let art = nowPlaying.artworkImage {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(white: 0.3), lineWidth: 0.5))
                        .shadow(color: Color.black.opacity(0.5), radius: 3)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.0, green: 0.96, blue: 0.83))
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.12)))
                }

                // Track Title & Artist
                VStack(alignment: .leading, spacing: 1) {
                    Text(nowPlaying.title.isEmpty ? "No Track" : nowPlaying.title)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    Text(nowPlaying.artist.isEmpty ? "Now Playing" : nowPlaying.artist)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(Color(white: 0.65))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Dancing Spectrum
                CyberAudioSpectrumView(barCount: 4, isPlaying: nowPlaying.isPlaying, barWidth: 2.2, segmentHeight: 1.8, segmentSpacing: 1.0)

                // Close button
                Button(action: {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        nowPlaying.showToast = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(Color(white: 0.4))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(red: 0.05, green: 0.06, blue: 0.08))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(red: 0.16, green: 0.19, blue: 0.24), lineWidth: 1))
            )
            .padding(.horizontal, 6)
            .padding(.bottom, 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sub-Notch Floating Synced Lyric Capsule (Free-Floating Satellite Island)

struct SubNotchFloatingLyricCapsuleView: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    var onOpenFull: () -> Void

    @State private var isHovered = false

    private var activeLyricText: String {
        nowPlaying.currentLyricText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: onOpenFull) {
            HStack(spacing: 6) {
                // Mini glowing lyric indicator icon
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(isHovered ? Color(red: 1.0, green: 0.16, blue: 0.53) : Color(red: 0.0, green: 0.96, blue: 0.83))

                // High-contrast live synced lyric text (Dynamically auto-expanding with zero clipping)
                Text(activeLyricText)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .id(activeLyricText)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))

                // Mini dancing cyber equalizer (3 bars)
                CyberAudioSpectrumView(
                    barCount: 3,
                    isPlaying: nowPlaying.isPlaying,
                    barWidth: 1.6,
                    segmentHeight: 1.3,
                    segmentSpacing: 0.6
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.95))
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.0, green: 0.96, blue: 0.83).opacity(isHovered ? 0.9 : 0.45),
                                        Color(red: 1.0, green: 0.16, blue: 0.53).opacity(isHovered ? 0.8 : 0.3)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(color: Color.black.opacity(0.85), radius: 6, x: 0, y: 3)
                    .shadow(color: Color(red: 0.0, green: 0.96, blue: 0.83).opacity(isHovered ? 0.25 : 0.08), radius: 4, x: 0, y: 1)
            )
            .frame(maxWidth: 520)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: activeLyricText)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help("♫ Live Synced Lyrics (Click to open Music HUD)")
    }
}

// Backward compatibility aliases
typealias SubNotchIntegratedLyricChinView = SubNotchFloatingLyricCapsuleView
typealias SubNotchLyricCapsuleView = SubNotchFloatingLyricCapsuleView

// MARK: - Redesigned High-Taste Compact Music HUD View with Synced Lyrics

struct CyberMusicHUDView: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    var appState: AppState
    @AppStorage(SettingsKey.showCompactLyrics) private var showCompactLyrics = SettingsDefaults.showCompactLyrics
    @AppStorage(SettingsKey.lyricSyncOffset) private var lyricSyncOffset = SettingsDefaults.lyricSyncOffset

    init(nowPlaying: NowPlayingManager, appState: AppState) {
        self.nowPlaying = nowPlaying
        self.appState = appState
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // LEFT COLUMN: Album Art, Track info, Scrubber & Controls (175pt fixed width)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    // Album Cover (48x48)
                    ZStack {
                        if let art = nowPlaying.artworkImage {
                            Image(nsImage: art)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(white: 0.25), lineWidth: 0.8))
                                .shadow(color: Color.black.opacity(0.5), radius: 3, y: 2)
                        } else {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                                .frame(width: 48, height: 48)
                                .overlay(Image(systemName: "music.note").font(.system(size: 18)).foregroundColor(Color(red: 0.0, green: 0.96, blue: 0.83)))
                        }
                    }
                    .id(nowPlaying.title + nowPlaying.artist)

                    // Track Title & Artist
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowPlaying.player.isEmpty ? "SPOTIFY" : nowPlaying.player.uppercased())
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 1.0, green: 0.16, blue: 0.53))

                        Text(nowPlaying.title.isEmpty ? "No track" : nowPlaying.title)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .id(nowPlaying.title)

                        Text(nowPlaying.artist.isEmpty ? "Idle" : nowPlaying.artist)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color(white: 0.65))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                // Interactive Scrubber
                VStack(spacing: 2) {
                    GeometryReader { geo in
                        let totalWidth = geo.size.width
                        let progressFraction: CGFloat = nowPlaying.trackDuration > 0
                            ? min(1.0, max(0.0, CGFloat(nowPlaying.playerPosition / nowPlaying.trackDuration)))
                            : 0.0

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(red: 0.14, green: 0.16, blue: 0.22))
                                .frame(height: 3)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(red: 0.0, green: 0.96, blue: 0.83))
                                .frame(width: totalWidth * progressFraction, height: 3)
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    guard nowPlaying.trackDuration > 0 else { return }
                                    let fraction = min(1.0, max(0.0, value.location.x / totalWidth))
                                    let targetTime = Double(fraction) * nowPlaying.trackDuration
                                    nowPlaying.seek(to: targetTime)
                                }
                        )
                    }
                    .frame(height: 4)

                    HStack {
                        Text(formatTime(nowPlaying.playerPosition))
                            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(white: 0.45))
                        Spacer()
                        Text(formatTime(nowPlaying.trackDuration))
                            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(white: 0.45))
                    }
                }

                // Playback Controls + Mini Disco
                HStack(spacing: 8) {
                    Button(action: { nowPlaying.previousTrack() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Color(white: 0.85))
                            .frame(width: 20, height: 20)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.11)))
                    }
                    .buttonStyle(.plain)

                    Button(action: { nowPlaying.togglePlayPause() }) {
                        Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                            .frame(width: 22, height: 20)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.05, green: 0.14, blue: 0.14)))
                    }
                    .buttonStyle(.plain)

                    Button(action: { nowPlaying.nextTrack() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Color(white: 0.85))
                            .frame(width: 20, height: 20)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.11)))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Retro Disco Visualizer (compact 6 bars)
                    CyberDiscoVisualizer(isPlaying: nowPlaying.isPlaying, barCount: 6, maxHeight: 16)
                }
            }
            .frame(width: 170)

            // Divider Rule (fixed height, never expands!)
            Rectangle()
                .fill(Color(red: 0.16, green: 0.19, blue: 0.24))
                .frame(width: 1, height: 92)

            // RIGHT COLUMN: Synced Real-Time Lyrics View (fixed height, compact!)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("LYRICS")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))

                    // Prominent Interactive Notch Lyrics Toggle Button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCompactLyrics.toggle()
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: showCompactLyrics ? "text.bubble.fill" : "text.bubble")
                                .font(.system(size: 6.5, weight: .bold))
                            Text(showCompactLyrics ? "SUB-NOTCH: ON" : "SUB-NOTCH: OFF")
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(showCompactLyrics ? Color.black : Color.white.opacity(0.65))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(showCompactLyrics ? Color(red: 0.0, green: 0.96, blue: 0.83) : Color(white: 0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(showCompactLyrics ? Color(red: 0.0, green: 0.96, blue: 0.83) : Color(white: 0.25), lineWidth: 0.75)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Turn ON/OFF live synced lyrics ticker directly below the notch cutout")

                    // Quick Timing Offset Nudge: [-0.25s] [Offset] [+0.25s]
                    HStack(spacing: 2) {
                        Button(action: {
                            lyricSyncOffset = min(3.0, max(-3.0, lyricSyncOffset - 0.25))
                        }) {
                            Text("-0.25s")
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1.5)
                                .background(RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.14)))
                        }
                        .buttonStyle(.plain)
                        .help("Delay lyrics (if lyrics are too fast)")

                        Text(String(format: "%+.2fs", lyricSyncOffset))
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(abs(lyricSyncOffset) > 0.01 ? Color(red: 0.0, green: 0.96, blue: 0.83) : Color.white.opacity(0.4))
                            .onTapGesture {
                                lyricSyncOffset = 0.0
                            }
                            .help("Click to reset offset to 0.00s")

                        Button(action: {
                            lyricSyncOffset = min(3.0, max(-3.0, lyricSyncOffset + 0.25))
                        }) {
                            Text("+0.25s")
                                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1.5)
                                .background(RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.14)))
                        }
                        .buttonStyle(.plain)
                        .help("Advance lyrics (if lyrics are too slow)")
                    }

                    Spacer()
                    if nowPlaying.lyricsLoading {
                        Text("LOADING...")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(Color(white: 0.45))
                    }
                }

                if nowPlaying.lyrics.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.6))
                        Text(nowPlaying.lyricsLoading ? "Fetching lyrics..." : "No lyrics found")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(Color(white: 0.45))
                    }
                    .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 78, alignment: .center)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 3.5) {
                                ForEach(nowPlaying.lyrics) { line in
                                    let isCurrent = (line.id == nowPlaying.currentLyricIndex)
                                    HStack(spacing: 4) {
                                        if isCurrent {
                                            Circle()
                                                .fill(Color(red: 0.0, green: 0.96, blue: 0.83))
                                                .frame(width: 3, height: 3)
                                        }
                                        Text(line.text)
                                            .font(.system(size: isCurrent ? 10 : 8.5, weight: isCurrent ? .bold : .regular, design: .monospaced))
                                            .foregroundStyle(isCurrent ? Color(red: 0.0, green: 0.96, blue: 0.83) : Color(white: 0.45))
                                            .lineLimit(2)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        nowPlaying.seek(to: line.timestamp)
                                    }
                                    .id(line.id)
                                }
                            }
                            .padding(.trailing, 4)
                        }
                        .frame(height: 78)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { _ in
                                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                                }
                        )
                        .onAppear {
                            proxy.scrollTo(nowPlaying.currentLyricIndex, anchor: .center)
                        }
                        .onChange(of: nowPlaying.currentLyricIndex) { _, newIndex in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 98)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(red: 0.05, green: 0.06, blue: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(red: 0.16, green: 0.19, blue: 0.24), lineWidth: 1)
                )
        )
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }
}

// MARK: - Machined Token Usage Badge (Kept for Agent View)

struct MachinedTokenBadge: View {
    var appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    private var tokenSnapshot: ClaudeUsageTotals? {
        appState.claudeUsage?.today
    }

    private var totalTokens: Int {
        guard let s = tokenSnapshot else { return 0 }
        return s.inputTokens + s.outputTokens + s.cacheCreationTokens + s.cacheReadTokens
    }

    private var tokenLabel: String {
        if totalTokens > 0 {
            return ClaudeUsageScanner.formatTokens(totalTokens)
        }
        let totalToolCalls = appState.sessions.values.reduce(0) { $0 + $1.totalToolCallCount }
        if totalToolCalls > 0 {
            return "\(totalToolCalls) ops"
        }
        return "0k"
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("⚡")
                .font(.system(size: 8))
                .foregroundColor(Color(red: 0.0, green: 0.96, blue: 0.83))
            Text(tokenLabel)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(red: 0.92, green: 0.94, blue: 0.98))
            Text("TOK")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(Color(white: 0.45))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.07, green: 0.08, blue: 0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(red: 0.16, green: 0.19, blue: 0.25), lineWidth: 0.75)
                )
        )
    }
}

// MARK: - Compatibility Aliases
typealias CyberMusicNotificationBanner = CyberMusicMiniPeekBanner
