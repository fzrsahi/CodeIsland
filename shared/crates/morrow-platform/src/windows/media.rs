//! Now Playing through SMTC (#107).
//!
//! `GlobalSystemMediaTransportControlsSessionManager` is the same surface the
//! media keys talk to: whichever player holds the session reports its own title,
//! artist, position and which controls it offers. Two consequences worth knowing:
//!
//! - A player that does not publish position gets `None` from us rather than a
//!   zero, so the card's extrapolator (`morrow_core::music::Position`) takes
//!   over exactly as it does on Linux when MPRIS sends no `Position`.
//! - `Controls` says which buttons to show: seeking, next and previous are per
//!   session, not per app.

use std::time::Duration;

use morrow_core::music::{Status, Track};
use windows::Media::Control::{
    GlobalSystemMediaTransportControlsSession as Session,
    GlobalSystemMediaTransportControlsSessionManager as Manager,
    GlobalSystemMediaTransportControlsSessionPlaybackStatus as Playback,
};
use windows::core::HSTRING;
use windows_future::IAsyncOperation;

/// `TimeSpan` counts 100-nanosecond ticks.
const TICKS_PER_MICROSECOND: i64 = 10;

/// The current session's track, or `None` when nothing is playing.
pub fn track() -> Result<Option<Track>, String> {
    let Some(session) = session()? else {
        return Ok(None);
    };
    let properties = session
        .TryGetMediaPropertiesAsync()
        .map_err(|error| error.message())?
        .join()
        .map_err(|error| error.message())?;
    let info = session.GetPlaybackInfo().map_err(|error| error.message())?;
    let status = match info.PlaybackStatus() {
        Ok(Playback::Playing) => Status::Playing,
        Ok(Playback::Paused) => Status::Paused,
        // `Closed`, `Changing`, `Stopped` and `Opened` all mean the same thing to
        // a card: nothing is coming out of the speakers.
        _ => Status::Stopped,
    };
    let title = string(properties.Title());
    let artist = string(properties.Artist());
    if title.is_empty() && artist.is_empty() {
        return Ok(None);
    }
    let controls = info.Controls().map_err(|error| error.message())?;
    let timeline = session
        .GetTimelineProperties()
        .map_err(|error| error.message())?;
    Ok(Some(Track {
        player: string(session.SourceAppUserModelId()),
        status,
        title,
        artist,
        album: string(properties.AlbumTitle()),
        length_us: ticks(
            timeline
                .EndTime()
                .map(|time| time.Duration)
                .unwrap_or_default(),
        ),
        // A player that never published a position reports zero; the card's
        // extrapolator handles the truth from then on.
        position_us: ticks(
            timeline
                .Position()
                .map(|time| time.Duration)
                .unwrap_or_default(),
        )
        .unwrap_or(0),
        can_seek: controls.IsPlaybackPositionEnabled().unwrap_or(false),
        can_go_next: controls.IsNextEnabled().unwrap_or(false),
        can_go_previous: controls.IsPreviousEnabled().unwrap_or(false),
    }))
}

pub fn play_pause() -> Result<(), String> {
    with(|session| session.TryTogglePlayPauseAsync()).map(|_| ())
}

pub fn next() -> Result<(), String> {
    with(|session| session.TrySkipNextAsync()).map(|_| ())
}

pub fn previous() -> Result<(), String> {
    with(|session| session.TrySkipPreviousAsync()).map(|_| ())
}

/// Seeks by an offset, if the session offers seeking at all. Returns the new
/// position in microseconds when Windows reports one.
pub fn seek_by(offset_us: i64) -> Result<Option<i64>, String> {
    let Some(session) = session()? else {
        return Ok(None);
    };
    let timeline = session
        .GetTimelineProperties()
        .map_err(|error| error.message())?;
    let current = timeline
        .Position()
        .map(|time| time.Duration)
        .unwrap_or_default();
    let start = timeline
        .StartTime()
        .map(|time| time.Duration)
        .unwrap_or_default();
    let end = timeline
        .EndTime()
        .map(|time| time.Duration)
        .unwrap_or_default();
    let target = (current + offset_us * TICKS_PER_MICROSECOND).clamp(start, end);
    session
        .TryChangePlaybackPositionAsync(target)
        .map_err(|error| error.message())?
        .join()
        .map_err(|error| error.message())?;
    Ok(Some(target / TICKS_PER_MICROSECOND))
}

/// The session Windows would show in its flyout.
fn session() -> Result<Option<Session>, String> {
    let manager: Manager = Manager::RequestAsync()
        .map_err(|error| error.message())?
        .join()
        .map_err(|error| error.message())?;
    manager
        .GetCurrentSession()
        .map(Some)
        .map_err(|error| error.message())
}

/// Runs an async media command and waits for it: the island's buttons are not a
/// UI thread with a message pump to spare.
fn with<F, T>(command: F) -> Result<T, String>
where
    F: FnOnce(&Session) -> windows::core::Result<IAsyncOperation<T>>,
    T: windows::core::RuntimeType + 'static,
{
    let session = session()?.ok_or_else(|| "nothing is playing".to_owned())?;
    command(&session)
        .map_err(|error| error.message())?
        .join()
        .map_err(|error| error.message())
}

fn string(value: windows::core::Result<HSTRING>) -> String {
    value.map(|text| text.to_string()).unwrap_or_default()
}

fn ticks(duration: i64) -> Option<i64> {
    (duration > 0).then_some(duration / TICKS_PER_MICROSECOND)
}

/// How long a media command is given before the card says it failed.
pub const TIMEOUT: Duration = Duration::from_secs(4);
