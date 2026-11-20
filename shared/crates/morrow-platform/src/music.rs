//! The music card's OS half (#102): `playerctl` for MPRIS, `wpctl` or `pactl`
//! for the volume, `curl` for lrclib. The readings themselves are
//! `morrow_core::music`; this runs the commands.
//!
//! Commands are injected (`Runner`) so a test can answer for a player without
//! one running, and so nothing here talks to D-Bus directly — the tools the
//! desktop already ships do, which keeps the dependency list where it is.

use morrow_core::music::{self, LyricLine, Track, Volume};

pub use crate::runner::{Runner, SystemRunner};

// MARK: - Now Playing

/// MPRIS through `playerctl`.
pub struct NowPlaying<'a> {
    runner: &'a dyn Runner,
    /// The clock the position is measured against, in milliseconds.
    now_ms: i64,
}

impl<'a> NowPlaying<'a> {
    pub fn new(runner: &'a dyn Runner, now_ms: i64) -> Self {
        Self { runner, now_ms }
    }

    /// The current track, or `None` when nothing is playing.
    pub fn track(&self) -> Result<Option<Track>, String> {
        let metadata = match self.runner.run(
            "playerctl",
            &["metadata", "--format", music::METADATA_FORMAT],
        ) {
            Ok(text) if !text.trim().is_empty() => text,
            // No player is not an error: the card simply has nothing to show.
            Ok(_) => return Ok(None),
            Err(error) if error.contains("No players found") => return Ok(None),
            Err(error) => return Err(error),
        };
        let mut track = music::parse_metadata(&metadata);
        // `Can*` are separate queries: they are properties, not metadata.
        for (property, set) in [
            ("canSeek", &mut track.can_seek),
            ("canGoNext", &mut track.can_go_next),
            ("canGoPrevious", &mut track.can_go_previous),
        ] {
            if let Ok(value) = self.runner.run(
                "playerctl",
                &["status", "--format", &format!("{{{{{property}}}}}")],
            ) {
                *set = music::parse_flag(&value);
            }
        }
        track.position_us = self.read_position(&metadata, &track)?;
        Ok(Some(track))
    }

    /// The position, stamped with the moment it was read. The metadata
    /// placeholder is already microseconds; `playerctl position` answers in
    /// seconds with fractions, so only the fallback needs converting.
    fn read_position(&self, _metadata: &str, track: &Track) -> Result<i64, String> {
        if track.position_us > 0 {
            return Ok(track.position_us);
        }
        let Ok(text) = self.runner.run("playerctl", &["position"]) else {
            return Ok(0);
        };
        let seconds: f64 = text
            .trim()
            .parse()
            .map_err(|_| "position: not a number".to_owned())?;
        Ok((seconds * 1_000_000.0) as i64)
    }

    /// The position this reading gives at `now_ms`, for a card that ticks.
    pub fn position(&self, track: &Track) -> music::Position {
        music::Position::new(
            track.position_us,
            self.now_ms,
            track.status,
            track.length_us,
        )
    }

    pub fn play_pause(&self) -> Result<(), String> {
        self.runner.run("playerctl", &["play-pause"]).map(|_| ())
    }

    pub fn next(&self) -> Result<(), String> {
        self.runner.run("playerctl", &["next"]).map(|_| ())
    }

    pub fn previous(&self) -> Result<(), String> {
        self.runner.run("playerctl", &["previous"]).map(|_| ())
    }

    /// Seek by an offset in microseconds, for the ±10 s buttons: `playerctl
    /// position 10+` moves forward ten seconds, `10-` back.
    pub fn seek_by(&self, offset_us: i64) -> Result<(), String> {
        let seconds = offset_us as f64 / 1_000_000.0;
        let sign = if seconds < 0.0 { "-" } else { "+" };
        let argument = format!("{}{sign}", seconds.abs());
        self.runner
            .run("playerctl", &["position", &argument])
            .map(|_| ())
    }
}

// MARK: - Volume

/// `wpctl` when it is there (PipeWire), `pactl` otherwise.
pub struct SystemVolume<'a> {
    runner: &'a dyn Runner,
    /// Which tool answered, so the setter uses the same one.
    tool: Option<Tool>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Tool {
    Wpctl,
    Pactl,
}

impl<'a> SystemVolume<'a> {
    pub fn new(runner: &'a dyn Runner) -> Self {
        Self { runner, tool: None }
    }

    pub fn read(&mut self) -> Result<Volume, String> {
        if let Ok(text) = self
            .runner
            .run("wpctl", &["get-volume", "@DEFAULT_AUDIO_SINK@"])
        {
            if let Some(volume) = music::parse_wpctl_volume(&text) {
                self.tool = Some(Tool::Wpctl);
                return Ok(volume);
            }
        }
        let volume = self
            .runner
            .run("pactl", &["get-sink-volume", "@DEFAULT_SINK@"])?;
        let mute = self
            .runner
            .run("pactl", &["get-sink-mute", "@DEFAULT_SINK@"])?;
        self.tool = Some(Tool::Pactl);
        music::parse_pactl_volume(&volume, &mute)
            .ok_or_else(|| "pactl: no volume in the output".to_owned())
    }

    /// Set the volume to `percent` (0–150).
    pub fn set_percent(&self, percent: u8) -> Result<(), String> {
        match self.tool.unwrap_or(Tool::Wpctl) {
            Tool::Wpctl => self
                .runner
                .run(
                    "wpctl",
                    &[
                        "set-volume",
                        "@DEFAULT_AUDIO_SINK@",
                        &format!("{}%", percent.min(150)),
                    ],
                )
                .map(|_| ()),
            Tool::Pactl => self
                .runner
                .run(
                    "pactl",
                    &[
                        "set-sink-volume",
                        "@DEFAULT_SINK@",
                        &format!("{}%", percent.min(150)),
                    ],
                )
                .map(|_| ()),
        }
    }

    pub fn toggle_mute(&self) -> Result<(), String> {
        match self.tool.unwrap_or(Tool::Wpctl) {
            Tool::Wpctl => self
                .runner
                .run("wpctl", &["set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
                .map(|_| ()),
            Tool::Pactl => self
                .runner
                .run("pactl", &["set-sink-mute", "@DEFAULT_SINK@", "toggle"])
                .map(|_| ()),
        }
    }
}

// MARK: - Lyrics

/// lrclib, the service macOS asks too.
pub const LRCLIB: &str = "https://lrclib.net/api/get";

/// Fetch the synced lyrics for a track. `None` when the service has none: not
/// an error, just a card without lyrics.
pub fn lyrics(runner: &dyn Runner, track: &Track) -> Result<Option<Vec<LyricLine>>, String> {
    if track.artist.is_empty() || track.title.is_empty() {
        return Ok(None);
    }
    let duration = track
        .length_us
        .map(|length| format!("{}", length / 1_000_000))
        .unwrap_or_default();
    let mut args = vec![
        "-fsS".to_owned(),
        "--max-time".to_owned(),
        "4".to_owned(),
        "-G".to_owned(),
        LRCLIB.to_owned(),
        "--data-urlencode".to_owned(),
        format!("artist_name={}", track.artist),
        "--data-urlencode".to_owned(),
        format!("track_name={}", track.title),
    ];
    if !duration.is_empty() {
        args.push("--data-urlencode".to_owned());
        args.push(format!("duration={duration}"));
    }
    let borrowed: Vec<&str> = args.iter().map(String::as_str).collect();
    let body = match runner.run("curl", &borrowed) {
        Ok(body) => body,
        // 404 means the service has no lyrics for this track.
        Err(error) if error.contains("exited 22") || error.contains("404") => return Ok(None),
        Err(error) => return Err(error),
    };
    let parsed: serde_json::Value =
        serde_json::from_str(&body).map_err(|error| format!("lrclib: {error}"))?;
    let synced = parsed
        .get("syncedLyrics")
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default();
    let lines = morrow_core::music::parse_lrc(synced);
    Ok((!lines.is_empty()).then_some(lines))
}
