//! The music card's commands (#102): what is playing, the controls, the volume
//! and the lyrics. The readings are `morrow_platform::music`; this only reads
//! the clock and hands the results to the card.
//!
//! No polling here: the card asks when it is open, which is the only time a
//! music card is on screen.

use std::sync::OnceLock;
use std::time::Instant;

use morrow_core::music::{LyricLine, Track};
use morrow_platform::music::{self, NowPlaying, SystemRunner, SystemVolume};

static RUNNER: SystemRunner = SystemRunner;

fn monotonic() -> i64 {
    static START: OnceLock<Instant> = OnceLock::new();
    let start = START.get_or_init(Instant::now);
    start.elapsed().as_millis() as i64
}

/// The current track, or `null` when nothing is playing.
#[tauri::command]
pub fn music_track() -> Result<Option<Track>, String> {
    NowPlaying::new(&RUNNER, monotonic()).track()
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
    NowPlaying::new(&RUNNER, monotonic()).play_pause()
}

#[tauri::command]
pub fn music_next() -> Result<(), String> {
    NowPlaying::new(&RUNNER, monotonic()).next()
}

#[tauri::command]
pub fn music_previous() -> Result<(), String> {
    NowPlaying::new(&RUNNER, monotonic()).previous()
}

/// Seek by an offset in microseconds (the ±10 s buttons).
#[tauri::command]
pub fn music_seek(offset_us: i64) -> Result<(), String> {
    NowPlaying::new(&RUNNER, monotonic()).seek_by(offset_us)
}

/// The system volume.
#[tauri::command]
pub fn music_volume() -> Result<morrow_core::music::Volume, String> {
    SystemVolume::new(&RUNNER).read()
}

#[tauri::command]
pub fn music_volume_set(percent: u8) -> Result<(), String> {
    SystemVolume::new(&RUNNER).set_percent(percent)
}

#[tauri::command]
pub fn music_volume_mute() -> Result<(), String> {
    SystemVolume::new(&RUNNER).toggle_mute()
}

/// Synced lyrics for a track, or `null` when the service has none.
#[tauri::command]
pub fn music_lyrics(track: Track) -> Result<Option<Vec<LyricLine>>, String> {
    music::lyrics(&RUNNER, &track)
}
