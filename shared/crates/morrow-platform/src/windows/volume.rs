//! The system volume through Core Audio (#107).
//!
//! `IAudioEndpointVolume` is the same thing the Windows volume flyout moves: one
//! COM object, a scalar in `0.0..=1.0` and a mute flag. No mixer to shell out to,
//! and no per-application indirection — the endpoint is the default output, which
//! is what the island's slider means.

use std::time::Duration;

use morrow_core::music::Volume;
use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
use windows::Win32::Media::Audio::{IMMDeviceEnumerator, MMDeviceEnumerator, eMultimedia, eRender};
use windows::Win32::System::Com::{
    CLSCTX_ALL, COINIT_APARTMENTTHREADED, CoCreateInstance, CoInitializeEx, CoUninitialize,
};

/// The default output's volume, or the sentence the card shows.
pub fn read() -> Result<Volume, String> {
    let endpoint = endpoint()?;
    let level =
        unsafe { endpoint.GetMasterVolumeLevelScalar() }.map_err(|error| error.message())?;
    let muted = unsafe { endpoint.GetMute() }
        .map_err(|error| error.message())?
        .as_bool();
    Ok(Volume {
        percent: percent(level),
        muted,
    })
}

/// Sets the volume, clamped to the 0–100 the card shows. Windows keeps its own
/// separate boost above 100%; that is not what a slider in a notch should do.
pub fn set_percent(percent: u8) -> Result<(), String> {
    let endpoint = endpoint()?;
    let scalar = f32::from(percent.min(100)) / 100.0;
    unsafe { endpoint.SetMasterVolumeLevelScalar(scalar, std::ptr::null()) }
        .map_err(|error| error.message())
}

/// Mutes, or unmutes, and says which it did.
pub fn toggle_mute() -> Result<bool, String> {
    let endpoint = endpoint()?;
    let muted = unsafe { endpoint.GetMute() }
        .map_err(|error| error.message())?
        .as_bool();
    unsafe { endpoint.SetMute(!muted, std::ptr::null()) }.map_err(|error| error.message())?;
    Ok(!muted)
}

/// A scalar to the percentage the card shows, rounded the way a user reads it.
pub fn percent(scalar: f32) -> u8 {
    (scalar.clamp(0.0, 1.0) * 100.0).round() as u8
}

/// COM, one apartment, one object at a time: the calls above are quick and
/// blocking by design, so the caller's thread can keep the apartment it has.
fn endpoint() -> Result<IAudioEndpointVolume, String> {
    unsafe {
        // `RPC_E_CHANGED_MODE` means another apartment mode is already set up on
        // this thread, which is fine: the object is usable either way.
        let initialised = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
        let enumerator: IMMDeviceEnumerator =
            CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)
                .map_err(|error| format!("Core Audio is unavailable: {}", error.message()))?;
        let device = enumerator
            .GetDefaultAudioEndpoint(eRender, eMultimedia)
            .map_err(|error| format!("no default output device: {}", error.message()))?;
        let activation = device
            .Activate::<IAudioEndpointVolume>(CLSCTX_ALL, None)
            .map_err(|error| format!("the endpoint volume is unavailable: {}", error.message()))?;
        // The object holds its own reference, so the apartment can be closed
        // while it lives; a caller that never initialised (the `Err` case) must
        // not uninitialise, or it unbalances someone else's apartment.
        if initialised.is_ok() {
            CoUninitialize();
        }
        Ok(activation)
    }
}

/// How long a volume change is given before the card reports it failed: COM
/// calls to the audio service are local, and a stuck one means the service is.
pub const TIMEOUT: Duration = Duration::from_secs(2);
