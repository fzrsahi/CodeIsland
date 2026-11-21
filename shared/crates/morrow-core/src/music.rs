//! Readings for the music card: MPRIS metadata as `playerctl` prints it, the
//! position extrapolated between updates, LRC lyrics, and the two volume
//! tools' output. Pure — the platform runs the commands (#102).
//!
//! The extrapolation is the interesting part: MPRIS `Position` is a snapshot
//! that a player is not required to refresh when it changes, so a card that
//! shows it raw freezes between updates. Given a position, the moment it was
//! read and whether the player is playing, every later position follows.

/// What the player is doing.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum Status {
    Playing,
    Paused,
    #[default]
    Stopped,
}

impl Status {
    pub fn parse(raw: &str) -> Self {
        match raw.trim().to_ascii_lowercase().as_str() {
            "playing" => Self::Playing,
            "paused" => Self::Paused,
            _ => Self::Stopped,
        }
    }

    pub fn is_playing(self) -> bool {
        self == Self::Playing
    }
}

/// One track, as the card shows it.
#[derive(Clone, Debug, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Track {
    pub player: String,
    pub status: Status,
    pub title: String,
    pub artist: String,
    pub album: String,
    /// `mpris:length`, in microseconds.
    pub length_us: Option<i64>,
    /// `Position`, in microseconds, when it was read.
    pub position_us: i64,
    /// Whether the player honours `Seek` (`CanSeek`).
    pub can_seek: bool,
    /// Whether the player has a next/previous track (`CanGoNext`/`CanGoPrevious`).
    pub can_go_next: bool,
    pub can_go_previous: bool,
}

/// `playerctl metadata --format` with tabs between the fields. A missing field
/// is an empty string, and a missing length/seek/next is `None`/false rather
/// than an error: many players omit them.
pub const METADATA_FORMAT: &str = "{{playerName}}\t{{status}}\t{{artist}}\t{{title}}\t{{album}}\t{{mpris:length}}\t{{position}}\t{{xesam:url}}";

/// Parse that format. `position_us` is 0 here — the caller stamps it — because
/// `playerctl` reads it at a moment only the caller knows.
pub fn parse_metadata(line: &str) -> Track {
    let fields: Vec<&str> = line.trim_end_matches('\n').split('\t').collect();
    let field = |index: usize| fields.get(index).copied().unwrap_or("").trim().to_owned();
    let number = |index: usize| -> Option<i64> {
        fields
            .get(index)
            .map(|value| value.trim())
            .and_then(|value| value.parse::<i64>().ok())
    };
    Track {
        player: field(0),
        status: Status::parse(&field(1)),
        artist: field(2),
        title: field(3),
        album: field(4),
        length_us: number(5).filter(|length| *length > 0),
        position_us: number(6).unwrap_or(0),
        can_seek: false,
        can_go_next: false,
        can_go_previous: false,
    }
}

/// `true`/`false` from `playerctl`'s `Can*` flags (`playerctl status
/// --format '{{canSeek}}'`).
pub fn parse_flag(raw: &str) -> bool {
    raw.trim().eq_ignore_ascii_case("true")
}

/// A position that keeps moving while the player does not say so.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Position {
    /// The last position the player reported, in microseconds.
    base_us: i64,
    /// When that reading was taken, in milliseconds on a monotonic clock.
    read_at_ms: i64,
    status: Status,
    length_us: Option<i64>,
}

impl Position {
    pub fn new(base_us: i64, read_at_ms: i64, status: Status, length_us: Option<i64>) -> Self {
        Self {
            base_us: base_us.max(0),
            read_at_ms,
            status,
            length_us,
        }
    }

    /// Where the track is at `now_ms` (the same clock as `read_at_ms`).
    ///
    /// Playing tracks advance; paused and stopped ones do not. A track that has
    /// run past its length stops at the length rather than running on — the
    /// next real reading corrects it if the player looped.
    pub fn at(&self, now_ms: i64) -> i64 {
        let elapsed_ms = (now_ms - self.read_at_ms).max(0);
        let mut position = self.base_us;
        if self.status.is_playing() {
            position += elapsed_ms.saturating_mul(1_000);
        }
        match self.length_us {
            Some(length) if length > 0 => position.min(length),
            _ => position,
        }
    }

    /// The fraction of the track that has played, 0.0–1.0, when the length is
    /// known.
    pub fn progress(&self, now_ms: i64) -> Option<f64> {
        let length = self.length_us.filter(|length| *length > 0)?;
        Some((self.at(now_ms) as f64 / length as f64).clamp(0.0, 1.0))
    }
}

/// One line of an LRC file.
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct LyricLine {
    /// Milliseconds from the start of the track.
    pub at_ms: i64,
    pub text: String,
}

/// Parse `syncedLyrics` from lrclib: `[mm:ss.xx] text`, several stamps allowed
/// per line, `[ar:]`-style metadata rows skipped.
pub fn parse_lrc(source: &str) -> Vec<LyricLine> {
    let mut lines: Vec<LyricLine> = Vec::new();
    for raw in source.lines() {
        let mut rest = raw.trim();
        let mut stamps: Vec<i64> = Vec::new();
        while let Some(after) = rest.strip_prefix('[') {
            let Some(close) = after.find(']') else { break };
            let inside = &after[..close];
            match parse_stamp(inside) {
                Some(at) => stamps.push(at),
                None => {
                    // A metadata tag (`ar:`, `ti:`, `offset:`): the whole line
                    // is not a lyric.
                    stamps.clear();
                    break;
                }
            }
            rest = &after[close + 1..];
        }
        let text = rest.trim();
        if text.is_empty() {
            continue;
        }
        for at in stamps {
            lines.push(LyricLine {
                at_ms: at,
                text: text.to_owned(),
            });
        }
    }
    lines.sort_by_key(|line| line.at_ms);
    lines
}

/// `mm:ss`, `mm:ss.xx` or `mm:ss.xxx`.
fn parse_stamp(inside: &str) -> Option<i64> {
    let (minutes, rest) = inside.split_once(':')?;
    let minutes: i64 = minutes.trim().parse().ok()?;
    let (seconds, fraction) = match rest.split_once('.') {
        Some((seconds, fraction)) => (seconds, Some(fraction)),
        None => (rest, None),
    };
    let seconds: i64 = seconds.trim().parse().ok()?;
    let millis = match fraction {
        Some(fraction) if !fraction.is_empty() => {
            let digits: String = fraction.chars().take(3).collect();
            let value: i64 = digits.parse().ok()?;
            match digits.len() {
                1 => value * 100,
                2 => value * 10,
                _ => value,
            }
        }
        _ => 0,
    };
    Some(minutes * 60_000 + seconds * 1_000 + millis)
}

/// The line being sung at `position_ms`, plus the one after it (for a card
/// that shows the next line faded).
pub fn lyrics_at(
    lines: &[LyricLine],
    position_ms: i64,
) -> (Option<&LyricLine>, Option<&LyricLine>) {
    let mut index: Option<usize> = None;
    for (position, line) in lines.iter().enumerate() {
        if line.at_ms <= position_ms {
            index = Some(position);
        } else {
            break;
        }
    }
    match index {
        Some(current) => (Some(&lines[current]), lines.get(current + 1)),
        None => (None, lines.first()),
    }
}

/// A volume reading from `wpctl`/`pactl`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Volume {
    /// 0–100.
    pub percent: u8,
    pub muted: bool,
}

/// `wpctl get-volume @DEFAULT_AUDIO_SINK@` → `Volume: 0.42` or
/// `Volume: 0.42 [MUTED]`.
pub fn parse_wpctl_volume(output: &str) -> Option<Volume> {
    let line = output
        .lines()
        .find(|line| line.trim_start().starts_with("Volume:"))?;
    let rest = line.trim_start().trim_start_matches("Volume:").trim();
    let scalar: f64 = rest.split_whitespace().next()?.parse().ok()?;
    Some(Volume {
        percent: (scalar * 100.0).round().clamp(0.0, 150.0) as u8,
        muted: output.to_ascii_uppercase().contains("[MUTED]"),
    })
}

/// `pactl get-sink-volume @DEFAULT_SINK@` → `Volume: front-left: 27525 /  42%
/// / …` (the first percentage is the volume), mute from
/// `pactl get-sink-mute`.
pub fn parse_pactl_volume(volume_output: &str, mute_output: &str) -> Option<Volume> {
    let line = volume_output.lines().find(|line| line.contains('%'))?;
    // The number immediately before the first `%`, not the raw volume level
    // that precedes it.
    let percent_at = line.find('%')?;
    let mut digits: Vec<char> = line[..percent_at]
        .chars()
        .rev()
        .take_while(char::is_ascii_digit)
        .collect();
    digits.reverse();
    let percent: u8 = digits.iter().collect::<String>().parse().ok()?;
    Some(Volume {
        percent: percent.min(150),
        muted: mute_output.trim().eq_ignore_ascii_case("Mute: yes"),
    })
}
