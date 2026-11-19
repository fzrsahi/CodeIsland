//! The sessions, the held permission requests, and their way to the
//! frontend: hooks are reduced as they arrive, and the snapshot is pushed
//! through the frontend's `Channel` at most once a frame (≤60 Hz), whatever
//! the hook rate.

use std::sync::mpsc::{self, Receiver};
use std::sync::{Arc, Condvar, Mutex, MutexGuard, PoisonError};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use morrow_protocol::HookPayload;
use serde::Serialize;
use tauri::ipc::Channel;

use crate::permissions::{Card, Decision, Permissions};
use crate::sessions::{Session, Sessions};

/// What the frontend receives (`Snapshot` in `src/App.svelte`).
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Snapshot {
    pub sessions: Vec<Session>,
    /// Held permission requests, oldest first.
    pub permissions: Vec<Card>,
}

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
    permissions: Permissions,
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

    /// Holds `payload` as a permission card; its decision arrives on the
    /// receiver.
    pub fn hold(&self, payload: &HookPayload) -> (u64, Receiver<Decision>) {
        let (answer, decision) = mpsc::channel();
        let id = self.change(|state| state.permissions.hold(payload, answer));
        (id, decision)
    }

    /// The user's answer to card `id`; false if it is no longer held.
    pub fn answer(&self, id: u64, decision: Decision) -> bool {
        self.change(|state| state.permissions.answer(id, decision))
    }

    /// Card `id`'s hook is gone.
    pub fn drop_request(&self, id: u64) {
        self.change(|state| state.permissions.drop_request(id));
    }

    fn change<T>(&self, f: impl FnOnce(&mut State) -> T) -> T {
        let mut state = self.lock();
        let result = f(&mut state);
        state.dirty = true;
        self.changed.notify_one();
        result
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
    /// `on_sent` is told how many sessions and cards each push carried.
    pub fn spawn_pusher(feed: Arc<Self>, on_sent: impl Fn(usize, usize) + Send + 'static) {
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
                        let snapshot = Snapshot {
                            sessions: state.sessions.snapshot(),
                            permissions: state.permissions.cards(),
                        };
                        (snapshot, state.channel.clone())
                    };
                    let counts = (snapshot.sessions.len(), snapshot.permissions.len());
                    if let Some(channel) = channel {
                        match channel.send(snapshot) {
                            Ok(()) => on_sent(counts.0, counts.1),
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
