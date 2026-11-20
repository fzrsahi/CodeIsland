//! The endpoint listener: one std thread accepting the bridge's
//! connections, one request and one reply each. A permission request is
//! held on a thread of its own until the panel answers or its hook goes.

use std::sync::Arc;
use std::sync::mpsc::RecvTimeoutError;
use std::thread;
use std::time::Duration;

use morrow_ipc::{Connection, Error, Server};
use morrow_protocol::{HookPayload, decode_payload};

use crate::feed::Feed;
use crate::permissions;

/// A bridge writes its request at once; one that stalls is dropped.
const READ_TIMEOUT: Duration = Duration::from_secs(2);
/// After an accept that failed for a reason other than the peer, so a
/// persistent error (out of descriptors) does not spin.
const ACCEPT_BACKOFF: Duration = Duration::from_millis(100);
/// How often a held request checks that its hook is still there.
const PEER_CHECK: Duration = Duration::from_millis(100);

pub fn spawn(server: Server, feed: Arc<Feed>) {
    thread::Builder::new()
        .name("morrow-listener".into())
        .spawn(move || {
            loop {
                match server.accept() {
                    Ok(connection) => serve(connection, &feed),
                    Err(error @ Error::PeerNotUser { .. }) => {
                        eprintln!("morrow-app: refused a connection: {error}");
                    }
                    Err(error) => {
                        eprintln!("morrow-app: accept: {error}");
                        thread::sleep(ACCEPT_BACKOFF);
                    }
                }
            }
        })
        .expect("spawn the listener thread");
}

fn serve(mut connection: Connection, feed: &Arc<Feed>) {
    let _ = connection.stream().set_read_timeout(Some(READ_TIMEOUT));
    let request = match connection.read_request() {
        Ok(request) => request,
        Err(error) => {
            eprintln!("morrow-app: read a request: {error}");
            return;
        }
    };
    // Another island's `Server::bind` probe: it connects and sends nothing.
    if request.is_empty() {
        return;
    }
    match decode_payload(&request) {
        Ok(payload) => {
            feed.record(&payload);
            if permissions::waits(&payload) {
                return hold(connection, &payload, feed);
            }
        }
        Err(error) => eprintln!("morrow-app: dropped a request: {error}"),
    }
    // Nobody waits: the empty reply at once, which the bridge reads as no
    // answer.
    if let Err(error) = connection.reply(b"") {
        eprintln!("morrow-app: reply: {error}");
    }
}

/// Holds the connection until the panel answers (the reply, then close) or
/// the hook goes (the card is dropped).
fn hold(connection: Connection, payload: &HookPayload, feed: &Arc<Feed>) {
    let (id, decision) = feed.hold(payload);
    let holder = Arc::clone(feed);
    let spawned = thread::Builder::new()
        .name(format!("morrow-held-{id}"))
        .spawn(move || {
            loop {
                match decision.recv_timeout(PEER_CHECK) {
                    Ok(decision) => {
                        if let Err(error) = connection.reply(decision.reply()) {
                            eprintln!("morrow-app: answer request {id}: {error}");
                        }
                        return;
                    }
                    Err(RecvTimeoutError::Timeout) if connection.peer_gone() => {
                        holder.drop_request(id);
                        return;
                    }
                    Err(RecvTimeoutError::Timeout) => {}
                    Err(RecvTimeoutError::Disconnected) => return,
                }
            }
        });
    if let Err(error) = spawned {
        eprintln!("morrow-app: hold request {id}: {error}");
        feed.drop_request(id);
    }
}
