//! The music card's commands (#102): what is playing, the controls, the volume
//! and the lyrics. The readings are `morrow_platform::music`; this only reads
//! the clock and hands the results to the card.
//!
//! No polling here: the card asks when it is open, which is the only time a
//! music card is on screen.

use std::sync::OnceLock;
use std::time::Instant;

use morrow_core::music::{LyricLine, Track};
// lrclib and the `Runner` are the same on both platforms; only the player and
// the volume differ (#107).
use morrow_platform::music::{self, SystemRunner};
#[cfg(unix)]
use morrow_platform::music::{NowPlaying, SystemVolume};

static RUNNER: SystemRunner = SystemRunner;

fn monotonic() -> i64 {
    static START: OnceLock<Instant> = OnceLock::new();
    let start = START.get_or_init(Instant::now);
    start.elapsed().as_millis() as i64
}

/// The current track, or `null` when nothing is playing. SMTC on Windows, MPRIS
/// through `playerctl` everywhere else (#107).
#[tauri::command]
pub fn music_track() -> Result<Option<Track>, String> {
    #[cfg(windows)]
    return morrow_platform::windows::media::track();
    #[cfg(unix)]
    return NowPlaying::new(&RUNNER, monotonic()).track();
}

/// Where the track is *now*, in microseconds: the card ticks without asking
/// the player again, and the player is not required to announce position.
#[tauri::command]
pub fn music_position(track: Track, read_at_ms: i64) -> i64 {
    morrow_core::music::Position::new(track.position_us, read_at_ms, track.status, track.length_us)
        .at(monotonic())
}

#[tauri::command]
pub fn music_play_pause() -> Result<(), String> {
    #[cfg(windows)]
    return morrow_platform::windows::media::play_pause();
    #[cfg(unix)]
    return NowPlaying::new(&RUNNER, monotonic()).play_pause();
}

#[tauri::command]
pub fn music_next() -> Result<(), String> {
    #[cfg(windows)]
    return morrow_platform::windows::media::next();
    #[cfg(unix)]
    return NowPlaying::new(&RUNNER, monotonic()).next();
}

#[tauri::command]
pub fn music_previous() -> Result<(), String> {
    #[cfg(windows)]
    return morrow_platform::windows::media::previous();
    #[cfg(unix)]
    return NowPlaying::new(&RUNNER, monotonic()).previous();
}

/// Seek by an offset in microseconds (the ±10 s buttons).
#[tauri::command]
pub fn music_seek(offset_us: i64) -> Result<(), String> {
    #[cfg(windows)]
    return morrow_platform::windows::media::seek_by(offset_us).map(|_| ());
    #[cfg(unix)]
    return NowPlaying::new(&RUNNER, monotonic()).seek_by(offset_us);
}

/// The system volume.
#[tauri::command]
pub fn music_volume() -> Result<morrow_core::music::Volume, String> {
    #[cfg(windows)]
    return morrow_platform::windows::volume::read();
    #[cfg(unix)]
    return SystemVolume::new(&RUNNER).read();
}

#[tauri::command]
pub fn music_volume_set(percent: u8) -> Result<(), String> {
    #[cfg(windows)]
    return morrow_platform::windows::volume::set_percent(percent);
    #[cfg(unix)]
    return SystemVolume::new(&RUNNER).set_percent(percent);
}

#[tauri::command]
pub fn music_volume_mute() -> Result<(), String> {
    #[cfg(windows)]
    return morrow_platform::windows::volume::toggle_mute().map(|_| ());
    #[cfg(unix)]
    return SystemVolume::new(&RUNNER).toggle_mute();
}

/// Synced lyrics for a track, or `null` when the service has none.
#[tauri::command]
pub fn music_lyrics(track: Track) -> Result<Option<Vec<LyricLine>>, String> {
    music::lyrics(&RUNNER, &track)
}
