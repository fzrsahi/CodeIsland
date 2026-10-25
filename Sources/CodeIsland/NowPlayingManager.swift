import Foundation
import Combine
import AppKit
import SwiftUI

// MARK: - Synced Lyric Model

struct LyricLine: Identifiable, Equatable, Sendable {
    let id: Int
    let timestamp: Double
    let text: String
}

/// Observes currently playing tracks from Apple Music and Spotify via macOS DistributedNotificationCenter and AppleScript.
/// Zero background overhead when idle, event-driven with smooth progress updates and lyrics when active.
@MainActor
final class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    @Published var isPlaying: Bool = false
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var album: String = ""
    @Published var player: String = "" // "Music" or "Spotify"
    @Published var artworkURL: String = ""
    @Published var artworkImage: NSImage?
    @Published var playerPosition: Double = 0
    @Published var trackDuration: Double = 0
    @Published var showToast: Bool = false
    @Published var lyrics: [LyricLine] = []
    @Published var currentLyricIndex: Int = 0
    @Published var lyricsLoading: Bool = false

    private var toastDismissTimer: Timer?
    private var progressTimer: Timer?
    private var lastFetchedLyricsKey: String = ""

    init() {
        setupObservers()
        fetchPlaybackDetails()
    }

    private func setupObservers() {
        let center = DistributedNotificationCenter.default()

        // Apple Music observer
        center.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAppleMusicNotification(notification)
            }
        }

        // Spotify observer
        center.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleSpotifyNotification(notification)
            }
        }
    }

    private func handleAppleMusicNotification(_ notification: Notification) {
        guard let info = notification.userInfo else { return }
        let state = info["Player State"] as? String ?? ""
        let playing = (state == "Playing")

        let trackTitle = info["Name"] as? String ?? ""
        let trackArtist = info["Artist"] as? String ?? ""
        let trackAlbum = info["Album"] as? String ?? ""

        updateBasicInfo(
            playing: playing,
            title: trackTitle,
            artist: trackArtist,
            album: trackAlbum,
            source: "Music"
        )
        fetchPlaybackDetails()
    }

    private func handleSpotifyNotification(_ notification: Notification) {
        guard let info = notification.userInfo else { return }
        let state = info["Player State"] as? String ?? ""
        let playing = (state == "Playing")

        let trackTitle = info["Name"] as? String ?? ""
        let trackArtist = info["Artist"] as? String ?? ""
        let trackAlbum = info["Album"] as? String ?? ""

        updateBasicInfo(
            playing: playing,
            title: trackTitle,
            artist: trackArtist,
            album: trackAlbum,
            source: "Spotify"
        )
        fetchPlaybackDetails()
    }

    private func updateBasicInfo(playing: Bool, title: String, artist: String, album: String, source: String) {
        let trackChanged = (self.title != title || self.artist != artist) && !title.isEmpty
        self.isPlaying = playing
        self.title = title
        self.artist = artist
        self.album = album
        self.player = source

        if playing {
            startProgressTimer()
            if trackChanged {
                triggerToast()
                fetchLyrics(title: title, artist: artist)
            }
        } else {
            stopProgressTimer()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                showToast = false
            }
            toastDismissTimer?.invalidate()
        }
    }

    func triggerToast() {
        toastDismissTimer?.invalidate()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            showToast = true
        }
        toastDismissTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    self?.showToast = false
                }
            }
        }
    }

    // MARK: - Playback Progress & Fetching

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isPlaying else { return }
                if self.trackDuration > 0 && self.playerPosition < self.trackDuration {
                    self.playerPosition += 0.5
                    self.updateCurrentLyricIndex()
                }
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    var currentLyricText: String {
        guard !lyrics.isEmpty, currentLyricIndex >= 0, currentLyricIndex < lyrics.count else { return "" }
        return lyrics[currentLyricIndex].text
    }

    private func updateCurrentLyricIndex() {
        guard !lyrics.isEmpty else { return }
        let offset = UserDefaults.standard.double(forKey: SettingsKey.lyricSyncOffset)
        let effectiveTime = max(0, playerPosition + offset)
        if let idx = lyrics.lastIndex(where: { $0.timestamp <= effectiveTime }) {
            if self.currentLyricIndex != idx {
                self.currentLyricIndex = idx
            }
        }
    }

    func fetchPlaybackDetails() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Try Spotify first
            let spotifyScript = """
            tell application "System Events"
                if exists (process "Spotify") then
                    tell application "Spotify"
                        set trackName to name of current track
                        set trackArtist to artist of current track
                        set trackAlbum to album of current track
                        set trackPos to player position
                        set trackDur to (duration of current track) / 1000
                        set artUrl to artwork url of current track
                        set pState to player state as string
                        return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & trackPos & "|||" & trackDur & "|||" & artUrl & "|||" & pState
                    end tell
                end if
            end tell
            """

            var output = Self.runAppleScript(spotifyScript)
            var detectedSource = "Spotify"

            // If Spotify returned empty, try Apple Music
            if output == nil || output?.isEmpty == true {
                let musicScript = """
                tell application "System Events"
                    if exists (process "Music") then
                        tell application "Music"
                            set trackName to name of current track
                            set trackArtist to artist of current track
                            set trackAlbum to album of current track
                            set trackPos to player position
                            set trackDur to duration of current track
                            set pState to player state as string
                            try
                                if exists (artwork 1 of current track) then
                                    set theData to data of artwork 1 of current track
                                    set theFile to (open for access POSIX file "/tmp/codeisland_music_art.png" with write permission)
                                    set eof theFile to 0
                                    write theData to theFile
                                    close access theFile
                                end if
                            on error
                                try
                                    close access file "/tmp/codeisland_music_art.png"
                                end try
                            end try
                            return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & trackPos & "|||" & trackDur & "|||/tmp/codeisland_music_art.png|||" & pState
                        end tell
                    end if
                end tell
                """
                output = Self.runAppleScript(musicScript)
                detectedSource = "Music"
            }

            guard let rawOutput = output, !rawOutput.isEmpty else { return }
            let parts = rawOutput.components(separatedBy: "|||")
            guard parts.count >= 7 else { return }

            let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let album = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let posStr = parts[3].replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
            let durStr = parts[4].replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
            let artPathOrUrl = parts[5].trimmingCharacters(in: .whitespacesAndNewlines)
            let state = parts[6].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            let pos = Double(posStr) ?? 0
            let dur = Double(durStr) ?? 0
            let playing = (state == "playing")

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.title = title
                self.artist = artist
                self.album = album
                self.playerPosition = pos
                self.trackDuration = dur
                self.isPlaying = playing
                self.player = detectedSource

                if playing {
                    self.startProgressTimer()
                } else {
                    self.stopProgressTimer()
                }

                // Load artwork if changed
                if self.artworkURL != artPathOrUrl {
                    self.artworkURL = artPathOrUrl
                    self.loadArtwork(from: artPathOrUrl)
                }

                // Fetch lyrics if not loaded
                if self.lyrics.isEmpty && !title.isEmpty {
                    self.fetchLyrics(title: title, artist: artist)
                }
            }
        }
    }

    private func loadArtwork(from pathOrUrl: String) {
        guard !pathOrUrl.isEmpty else {
            self.artworkImage = nil
            return
        }

        if pathOrUrl.hasPrefix("http") {
            guard let url = URL(string: pathOrUrl) else { return }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                if let data = data, let img = NSImage(data: data) {
                    Task { @MainActor in
                        self?.artworkImage = img
                    }
                }
            }.resume()
        } else if FileManager.default.fileExists(atPath: pathOrUrl) {
            if let img = NSImage(contentsOfFile: pathOrUrl) {
                self.artworkImage = img
            }
        }
    }

    // MARK: - Lyrics Engine

    func fetchLyrics(title: String, artist: String) {
        let key = "\(title):::\(artist)"
        guard key != lastFetchedLyricsKey && !title.isEmpty else { return }
        lastFetchedLyricsKey = key
        lyricsLoading = true

        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://lrclib.net/api/get?track_name=\(encodedTitle)&artist_name=\(encodedArtist)") else {
            lyricsLoading = false
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            defer {
                Task { @MainActor in self?.lyricsLoading = false }
            }
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            var parsed: [LyricLine] = []
            if let synced = json["syncedLyrics"] as? String, !synced.isEmpty {
                parsed = Self.parseLRC(synced)
            } else if let plain = json["plainLyrics"] as? String, !plain.isEmpty {
                let rawLines = plain.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                parsed = rawLines.enumerated().map { LyricLine(id: $0.offset, timestamp: Double($0.offset) * 4.0, text: $0.element) }
            }

            Task { @MainActor in
                self?.lyrics = parsed
                self?.currentLyricIndex = 0
            }
        }.resume()
    }

    nonisolated private static func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let rawLines = lrc.components(separatedBy: .newlines)
        var idCounter = 0
        for line in rawLines {
            guard line.hasPrefix("["), let closingBracket = line.firstIndex(of: "]") else { continue }
            let timePart = String(line[line.index(after: line.startIndex)..<closingBracket])
            let textPart = String(line[line.index(after: closingBracket)...]).trimmingCharacters(in: .whitespaces)
            let timeParts = timePart.components(separatedBy: ":")
            if timeParts.count == 2,
               let min = Double(timeParts[0]),
               let sec = Double(timeParts[1]) {
                let total = min * 60 + sec
                if !textPart.isEmpty {
                    lines.append(LyricLine(id: idCounter, timestamp: total, text: textPart))
                    idCounter += 1
                }
            }
        }
        return lines
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        let app = player.isEmpty ? "Spotify" : player
        let script = "tell application \"\(app)\" to playpause"
        _ = Self.runAppleScript(script)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.fetchPlaybackDetails()
        }
    }

    func nextTrack() {
        let app = player.isEmpty ? "Spotify" : player
        let script = "tell application \"\(app)\" to next track"
        _ = Self.runAppleScript(script)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.fetchPlaybackDetails()
            self?.triggerToast()
        }
    }

    func previousTrack() {
        let app = player.isEmpty ? "Spotify" : player
        let script = "tell application \"\(app)\" to previous track"
        _ = Self.runAppleScript(script)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.fetchPlaybackDetails()
            self?.triggerToast()
        }
    }

    func seek(to position: Double) {
        let app = player.isEmpty ? "Spotify" : player
        let script = "tell application \"\(app)\" to set player position to \(position)"
        _ = Self.runAppleScript(script)
        self.playerPosition = position
        updateCurrentLyricIndex()
    }

    nonisolated private static func runAppleScript(_ script: String) -> String? {
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if error == nil {
                return result.stringValue
            }
        }
        return nil
    }
}
