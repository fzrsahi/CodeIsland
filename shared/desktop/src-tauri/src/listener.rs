//! The endpoint listener: one std thread accepting the bridge's
//! connections, one request and one reply each.

use std::sync::Arc;
use std::thread;
use std::time::Duration;

use morrow_ipc::unix::{Connection, Error, Server};
use morrow_protocol::decode_payload;

use crate::feed::Feed;

/// A bridge writes its request at once; one that stalls is dropped.
const READ_TIMEOUT: Duration = Duration::from_secs(2);
/// After an accept that failed for a reason other than the peer, so a
/// persistent error (out of descriptors) does not spin.
const ACCEPT_BACKOFF: Duration = Duration::from_millis(100);

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

fn serve(mut connection: Connection, feed: &Feed) {
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
        Ok(payload) => feed.record(&payload),
        Err(error) => eprintln!("morrow-app: dropped a request: {error}"),
    }
    // TODO(#91): a hook that waits (PermissionRequest, a question) holds its
    // connection until the panel answers. Until then every hook gets the
    // empty reply at once, which the bridge reads as no answer.
    if let Err(error) = connection.reply(b"") {
        eprintln!("morrow-app: reply: {error}");
    }
}
