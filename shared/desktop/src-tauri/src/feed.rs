//! The sessions and their way to the frontend: hooks are reduced as they
//! arrive, and the snapshot is pushed through the frontend's `Channel` at
//! most once a frame (≤60 Hz), whatever the hook rate.

use std::sync::{Arc, Condvar, Mutex, MutexGuard, PoisonError};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use morrow_protocol::HookPayload;
use tauri::ipc::Channel;

use crate::sessions::{Sessions, Snapshot};

/// One push per 1/60 s at most.
const FRAME: Duration = Duration::from_micros(16_667);

#[derive(Default)]
pub struct Feed {
    state: Mutex<State>,
    changed: Condvar,
}

#[derive(Default)]
struct State {
    sessions: Sessions,
    channel: Option<Channel<Snapshot>>,
    /// The frontend has not seen the latest snapshot.
    dirty: bool,
}

impl Feed {
    /// Reduces one hook into the sessions.
    pub fn record(&self, payload: &HookPayload) {
        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |d| u64::try_from(d.as_millis()).unwrap_or(u64::MAX));
        let mut state = self.lock();
        state.sessions.apply(payload, now_ms);
        state.dirty = true;
        self.changed.notify_one();
    }

    /// Sends snapshots to `channel` from now on, the current one first. A
    /// reloaded frontend subscribes again and replaces the old channel.
    pub fn subscribe(&self, channel: Channel<Snapshot>) {
        let mut state = self.lock();
        state.channel = Some(channel);
        state.dirty = true;
        self.changed.notify_one();
    }

    /// Pushes snapshots forever: waits for a change, sends, waits a frame.
    /// `on_sent` is told how many sessions each push carried.
    pub fn spawn_pusher(feed: Arc<Self>, on_sent: impl Fn(usize) + Send + 'static) {
        thread::Builder::new()
            .name("morrow-feed".into())
            .spawn(move || {
                loop {
                    let (snapshot, channel) = {
                        let mut state = feed.lock();
                        while !(state.dirty && state.channel.is_some()) {
                            state = feed
                                .changed
                                .wait(state)
                                .unwrap_or_else(PoisonError::into_inner);
                        }
                        state.dirty = false;
                        (state.sessions.snapshot(), state.channel.clone())
                    };
                    let count = snapshot.sessions.len();
                    if let Some(channel) = channel {
                        match channel.send(snapshot) {
                            Ok(()) => on_sent(count),
                            Err(error) => eprintln!("morrow-app: push to the frontend: {error}"),
                        }
                    }
                    thread::sleep(FRAME);
                }
            })
            .expect("spawn the feed thread");
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }
}
