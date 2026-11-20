//! `morrow-app`: the Tauri v2 shell on Linux (ADR-0002). Listens at the
//! endpoint, reduces each hook into a session list, and shows it in a
//! tight-fit, nonactivating panel, which answers permission requests.

mod feed;
mod hooks;
mod island;
mod listener;
mod permissions;
mod sessions;

use std::process::ExitCode;
use std::sync::Arc;

use morrow_ipc::unix::{Error, Server, current_endpoint};
use tauri::State;
use tauri::ipc::Channel;

use crate::feed::{Feed, Snapshot};
use crate::island::Smoke;
use crate::permissions::Decision;

/// Where the hook installer works: this user's home and the Claude Code config
/// directory, resolved once at launch.
pub struct HooksSite {
    pub paths: morrow_platform::hooks::Paths,
    pub opencode: morrow_platform::opencode::Site,
    pub kimi: morrow_platform::kimi::Site,
    pub yaml: Vec<morrow_platform::yaml_hooks::Site>,
    pub bridge_source: Option<std::path::PathBuf>,
}

/// The frontend's channel for snapshots.
#[tauri::command]
fn subscribe(feed: State<'_, Arc<Feed>>, channel: Channel<Snapshot>) {
    feed.subscribe(channel);
}

/// The user's Approve or Deny on card `id`. False if the request is no
/// longer held (answered already, or its hook gone).
#[tauri::command]
fn answer_permission(feed: State<'_, Arc<Feed>>, id: u64, decision: Decision) -> bool {
    feed.answer(id, decision)
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

    let hooks_site = hooks::site();
    let feed = Arc::new(Feed::default());
    listener::spawn(server, Arc::clone(&feed));
    Feed::spawn_pusher(Arc::clone(&feed), move |sessions, cards| {
        if smoke {
            println!("morrow-smoke: pushed sessions={sessions} cards={cards}");
        }
    });

    let result = tauri::Builder::default()
        .manage(feed)
        .manage(hooks_site)
        .manage(Smoke(smoke))
        .invoke_handler(tauri::generate_handler![
            subscribe,
            answer_permission,
            island::set_island_size,
            island::smoke_card,
            hooks::hooks_status,
            hooks::hooks_install,
            hooks::hooks_uninstall,
            hooks::target_install,
            hooks::target_uninstall,
            hooks::opencode_install,
            hooks::opencode_uninstall,
            hooks::kimi_install,
            hooks::kimi_uninstall,
            hooks::yaml_install,
            hooks::yaml_uninstall
        ])
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
