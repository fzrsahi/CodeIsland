//! The golden fixtures (`fixtures/*/bridge-golden.json`, exported from the
//! Swift suite) through this crate: every forwarded payload in every bundle
//! decodes, and encodes back to the bytes it was recorded as.

use std::collections::BTreeMap;
use std::path::PathBuf;

use morrow_protocol::{
    EdgeFacts, Envelope, HookPayload, ProtocolError, decode_envelope, decode_payload,
    encode_envelope, encode_payload,
};
use serde_json::Value;
use serde_json::value::RawValue;

/// Where the golden fixtures live, from the repository root. The monorepo
/// move (#86) changes this to `shared/contract/fixtures`; nothing else
/// names the path.
const FIXTURE_ROOT: &str = "fixtures";

const SCOPES: &[&str] = &["neutral", "macos", "linux", "windows"];

type RawObject = BTreeMap<String, Box<RawValue>>;

struct Fixture {
    scope: &'static str,
    name: String,
    /// The forwarded payload as recorded, whitespace removed; `None` when the
    /// bridge forwards nothing.
    forwarded: Option<String>,
    /// The agent's stdin (neutral bundle only).
    stdin: Option<String>,
}

fn bundle_path(scope: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .join(FIXTURE_ROOT)
        .join(scope)
        .join("bridge-golden.json")
}

fn load(scope: &'static str) -> Vec<Fixture> {
    let path = bundle_path(scope);
    let text = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", path.display()));
    let bundle: RawObject = serde_json::from_str(&text).expect("bundle is a JSON object");
    let fixtures: Vec<RawObject> =
        serde_json::from_str(bundle["fixtures"].get()).expect("`fixtures` is an array");
    assert!(!fixtures.is_empty(), "{scope}: no fixtures");
    fixtures
        .into_iter()
        .map(|fixture| {
            let name: String = serde_json::from_str(fixture["name"].get()).expect("name");
            let expectation: RawObject =
                serde_json::from_str(fixture["expectation"].get()).expect("expectation");
            let forwarded = minify(expectation["forwarded"].get());
            let stdin = fixture.get("input").map(|input| {
                let input: RawObject = serde_json::from_str(input.get()).expect("input");
                serde_json::from_str(input["stdin"].get()).expect("stdin is a string")
            });
            Fixture {
                scope,
                name,
                forwarded: (forwarded != "null").then_some(forwarded),
                stdin,
            }
        })
        .collect()
}

fn all() -> Vec<Fixture> {
    SCOPES.iter().flat_map(|scope| load(scope)).collect()
}

/// `text` without the whitespace a pretty printer put between tokens.
fn minify(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let (mut in_string, mut escaped) = (false, false);
    for c in text.chars() {
        if in_string {
            out.push(c);
            match (escaped, c) {
                (true, _) => escaped = false,
                (false, '\\') => escaped = true,
                (false, '"') => in_string = false,
                _ => {}
            }
        } else if c == '"' {
            in_string = true;
            out.push(c);
        } else if !c.is_whitespace() {
            out.push(c);
        }
    }
    out
}

fn decoded(fixture: &Fixture, bytes: &[u8]) -> HookPayload {
    decode_payload(bytes).unwrap_or_else(|e| panic!("{}/{}: {e}", fixture.scope, fixture.name))
}

#[test]
fn every_bundle_names_only_neutral_fixtures() {
    let neutral: Vec<String> = load("neutral").into_iter().map(|f| f.name).collect();
    for scope in &SCOPES[1..] {
        let names: Vec<String> = load(scope).into_iter().map(|f| f.name).collect();
        assert_eq!(names, neutral, "{scope} lists other fixtures than neutral");
    }
}

#[test]
fn forwarded_payloads_round_trip_byte_identical() {
    let mut cases = 0;
    for fixture in all() {
        let Some(bytes) = &fixture.forwarded else {
            continue;
        };
        let payload = decoded(&fixture, bytes.as_bytes());
        assert_eq!(
            String::from_utf8(encode_payload(&payload)).unwrap(),
            *bytes,
            "{}/{}",
            fixture.scope,
            fixture.name
        );
        let value: Value = serde_json::from_str(bytes).unwrap();
        assert_eq!(Value::Object(payload.as_object().clone()), value);
        assert!(!payload.session_id().is_empty());
        cases += 1;
    }
    assert!(cases > 0);
    eprintln!("forwarded payload cases: {cases}");
}

#[test]
fn forwarded_payloads_keep_key_order() {
    // The recordings list keys sorted; a payload arrives in any order, and
    // must leave in the same one.
    for fixture in all() {
        let Some(bytes) = &fixture.forwarded else {
            continue;
        };
        let sorted = decoded(&fixture, bytes.as_bytes());
        let reversed: Vec<String> = sorted
            .as_object()
            .iter()
            .rev()
            .map(|(k, v)| format!("{}:{}", Value::from(k.as_str()), v))
            .collect();
        let reversed = format!("{{{}}}", reversed.join(","));
        let payload = decoded(&fixture, reversed.as_bytes());
        assert_eq!(
            String::from_utf8(encode_payload(&payload)).unwrap(),
            reversed,
            "{}/{}",
            fixture.scope,
            fixture.name
        );
    }
}

#[test]
fn forwarded_payloads_round_trip_in_ipc_envelope() {
    for fixture in all() {
        let Some(bytes) = &fixture.forwarded else {
            continue;
        };
        let envelope = format!(r#"{{"v":1,"payload":{bytes}}}"#);
        let decoded = decode_envelope(envelope.as_bytes())
            .unwrap_or_else(|e| panic!("{}/{}: {e}", fixture.scope, fixture.name));
        let Envelope::Ipc(payload) = &decoded else {
            panic!("{}/{}: not an IPC envelope", fixture.scope, fixture.name)
        };
        assert_eq!(String::from_utf8(encode_payload(payload)).unwrap(), *bytes);
        assert_eq!(
            String::from_utf8(encode_envelope(&decoded)).unwrap(),
            envelope
        );
    }
}

/// `docs/hook-edge-protocol.md`'s example facts.
const EDGE: &str = r#"{"v":1,"source":"claude","cwd":"/home/dev/project","tty":"/dev/pts/3","host":{"id":"devbox","name":"Dev Box"},"stdin_sha256":"9f2c00aa","waits":true}"#;

#[test]
fn agent_stdin_with_edge_facts_round_trips_byte_identical() {
    let mut cases = 0;
    for fixture in load("neutral") {
        let stdin = fixture.stdin.as_deref().unwrap();
        let Ok(Value::Object(object)) = serde_json::from_str::<Value>(stdin) else {
            continue;
        };
        let bytes = if object.is_empty() {
            format!(r#"{{"_edge":{EDGE}}}"#)
        } else {
            format!(r#"{},"_edge":{EDGE}}}"#, &stdin[..stdin.len() - 1])
        };
        let decoded = decode_envelope(bytes.as_bytes())
            .unwrap_or_else(|e| panic!("neutral/{}: {e}", fixture.name));
        let Envelope::Edge(edge) = &decoded else {
            panic!("neutral/{}: not an edge payload", fixture.name)
        };
        let facts: &EdgeFacts = edge.facts();
        assert_eq!(facts.v, 1);
        assert_eq!(facts.source.as_deref(), Some("claude"));
        assert_eq!(facts.waits, Some(true));
        let host = facts.host.as_ref().unwrap();
        assert_eq!(
            (host.id.as_str(), host.name.as_deref()),
            ("devbox", Some("Dev Box"))
        );
        assert!(facts.other.is_empty());
        assert_eq!(
            String::from_utf8(encode_envelope(&decoded)).unwrap(),
            bytes,
            "neutral/{}",
            fixture.name
        );
        cases += 1;
    }
    assert!(cases > 0);
    eprintln!("edge payload cases: {cases}");
}

#[test]
fn agent_stdin_that_is_no_object_is_refused() {
    let mut cases = 0;
    for fixture in load("neutral") {
        let stdin = fixture.stdin.as_deref().unwrap();
        if matches!(serde_json::from_str::<Value>(stdin), Ok(Value::Object(_))) {
            continue;
        }
        let error = decode_envelope(stdin.as_bytes()).unwrap_err();
        assert!(
            matches!(
                error,
                ProtocolError::Json(_) | ProtocolError::NotAnObject { .. }
            ),
            "neutral/{}: {error}",
            fixture.name
        );
        assert!(decode_payload(stdin.as_bytes()).is_err());
        cases += 1;
    }
    assert!(cases > 0);
    eprintln!("non-object stdin cases: {cases}");
}
