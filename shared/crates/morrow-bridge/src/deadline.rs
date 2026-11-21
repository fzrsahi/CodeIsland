//! The Swift bridge's `alarm(2)` deadlines, as a thread: past the armed
//! deadline the process exits 0 at once, wherever the main thread is stuck.

use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::thread;
use std::time::{Duration, Instant};

/// Exits the process with status 0 when an armed deadline passes.
#[derive(Debug)]
pub struct Deadline {
    tx: Sender<Option<Duration>>,
}

impl Deadline {
    /// Starts the watcher, unarmed. `None` if the thread cannot start: the
    /// bridge then runs without deadlines rather than not at all.
    pub fn start() -> Option<Self> {
        let (tx, rx) = mpsc::channel::<Option<Duration>>();
        thread::Builder::new()
            .name("deadline".into())
            .spawn(move || {
                let mut deadline: Option<Instant> = None;
                loop {
                    let message = match deadline {
                        None => match rx.recv() {
                            Ok(message) => message,
                            Err(_) => return,
                        },
                        Some(at) => {
                            let left = at.saturating_duration_since(Instant::now());
                            match rx.recv_timeout(left) {
                                Ok(message) => message,
                                Err(RecvTimeoutError::Timeout) => std::process::exit(0),
                                Err(RecvTimeoutError::Disconnected) => return,
                            }
                        }
                    };
                    deadline = message.map(|after| Instant::now() + after);
                }
            })
            .ok()?;
        Some(Self { tx })
    }

    /// Exit 0 once `after` has passed, replacing any deadline armed before.
    pub fn arm(&self, after: Duration) {
        let _ = self.tx.send(Some(after));
    }

    /// No deadline: wait as long as it takes.
    pub fn disarm(&self) {
        let _ = self.tx.send(None);
    }
}
