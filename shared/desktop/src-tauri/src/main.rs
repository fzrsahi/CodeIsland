//! `morrow-app`: the Tauri v2 shell on Linux (ADR-0002). Listens at the
//! endpoint, reduces each hook into a session list, and shows it in a
//! tight-fit, nonactivating panel.

mod feed;
mod island;
mod listener;
mod sessions;

use std::process::ExitCode;
use std::sync::Arc;

use morrow_ipc::unix::{Error, Server, current_endpoint};
use tauri::State;
use tauri::ipc::Channel;

use crate::feed::Feed;
use crate::island::Smoke;
use crate::sessions::Snapshot;

/// The frontend's channel for snapshots.
#[tauri::command]
fn subscribe(feed: State<'_, Arc<Feed>>, channel: Channel<Snapshot>) {
    feed.subscribe(channel);
}

fn main() -> ExitCode {
    let smoke = std::env::var("MORROW_SMOKE").is_ok_and(|v| v == "1");

    let endpoint = current_endpoint();
    let server = match Server::bind(&endpoint) {
        Ok(server) => server,
        Err(Error::AlreadyRunning { path }) => {
            eprintln!("morrow-app: an island already listens at {path}, exiting");
            return ExitCode::SUCCESS;
        }
        Err(error) => {
            eprintln!("morrow-app: cannot listen at {endpoint}: {error}");
            return ExitCode::FAILURE;
        }
    };
    if smoke {
        println!("morrow-smoke: listening {}", server.path());
    }

    let feed = Arc::new(Feed::default());
    listener::spawn(server, Arc::clone(&feed));
    Feed::spawn_pusher(Arc::clone(&feed), move |count| {
        if smoke {
            println!("morrow-smoke: pushed sessions={count}");
        }
    });

    let result = tauri::Builder::default()
        .manage(feed)
        .manage(Smoke(smoke))
        .invoke_handler(tauri::generate_handler![subscribe, island::set_island_size])
        .setup(|app| Ok(island::create(app)?))
        .run(tauri::generate_context!());
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("morrow-app: {error}");
            ExitCode::FAILURE
        }
    }
}
