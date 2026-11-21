//! What the schemas refuse, and what they let through.

use morrow_protocol::{
    Envelope, PidOrToken, ProtocolError, decode_envelope, decode_payload, encode_envelope,
    encode_payload,
};

const PAYLOAD: &str = r#"{"session_id":"s-1","hook_event_name":"Stop"}"#;

fn missing(error: ProtocolError) -> String {
    match error {
        ProtocolError::MissingField { field } => field,
        other => panic!("expected MissingField, got {other:?}"),
    }
}

fn invalid(error: ProtocolError) -> String {
    match error {
        ProtocolError::InvalidField { field, .. } => field,
        other => panic!("expected InvalidField, got {other:?}"),
    }
}

#[test]
fn payload_that_is_no_object_is_refused() {
    for (bytes, found) in [
        ("[1,2]", "an array"),
        ("\"x\"", "a string"),
        ("null", "null"),
        ("3", "a number"),
    ] {
        match decode_payload(bytes.as_bytes()).unwrap_err() {
            ProtocolError::NotAnObject { field, found: f } => {
                assert_eq!((field.as_str(), f), ("payload", found));
            }
            other => panic!("{bytes}: {other:?}"),
        }
    }
    for bytes in ["", "not json", "{\"a\":"] {
        assert!(matches!(
            decode_payload(bytes.as_bytes()),
            Err(ProtocolError::Json(_))
        ));
    }
}

#[test]
fn payload_needs_event_and_session() {
    assert_eq!(
        missing(decode_payload(br#"{"session_id":"s-1"}"#).unwrap_err()),
        "hook_event_name"
    );
    assert_eq!(
        missing(decode_payload(br#"{"hook_event_name":"Stop"}"#).unwrap_err()),
        "session_id"
    );
    assert_eq!(
        invalid(decode_payload(br#"{"hook_event_name":"Stop","session_id":""}"#).unwrap_err()),
        "session_id"
    );
}

#[test]
fn payload_fields_have_the_schemas_types() {
    for (extra, field) in [
        (r#""_ppid":-1"#, "_ppid"),
        (r#""_ppid":"PID0""#, "_ppid"),
        (r#""_via_plugin":"yes""#, "_via_plugin"),
        (
            r#""_cursor_payload_digest":"abc""#,
            "_cursor_payload_digest",
        ),
        (r#""_env":{"TERM":1}"#, "_env"),
        (r#""_zellij_tab":7"#, "_zellij_tab"),
        (r#""tool_input":"ls""#, "tool_input"),
    ] {
        let bytes = format!(r#"{{"hook_event_name":"Stop","session_id":"s",{extra}}}"#);
        assert_eq!(
            invalid(decode_payload(bytes.as_bytes()).unwrap_err()),
            field
        );
    }
}

#[test]
fn payload_keeps_unknown_keys_in_order_and_reads_known_ones() {
    let bytes = br#"{"zeta":{"b":1,"a":[2,{"y":0,"x":1}]},"_ppid":"$PID0","session_id":"s-1","_tty":null,"_term_app":"WezTerm","hook_event_name":"","_hook_ppid":42,"_source":"codex","alpha":1.5}"#;
    let payload = decode_payload(bytes).unwrap();
    assert_eq!(encode_payload(&payload), bytes);
    assert_eq!(payload.hook_event_name(), "");
    assert_eq!(payload.session_id(), "s-1");
    assert_eq!(payload.source(), Some("codex"));
    assert_eq!(payload.ppid(), Some(PidOrToken::Token("$PID0")));
    assert_eq!(payload.hook_ppid(), Some(PidOrToken::Pid(42)));
    assert_eq!(
        payload.terminal().collect::<Vec<_>>(),
        [("_term_app", "WezTerm")]
    );
    assert!(payload.edge().is_none());
}

#[test]
fn envelope_reads_version_one_only() {
    let v1 = format!(r#"{{"v":1,"payload":{PAYLOAD}}}"#);
    let decoded = decode_envelope(v1.as_bytes()).unwrap();
    assert!(matches!(&decoded, Envelope::Ipc(p) if p.session_id() == "s-1"));
    assert_eq!(encode_envelope(&decoded), v1.as_bytes());

    for v in ["2", "0", "-1"] {
        let bytes = format!(r#"{{"v":{v},"payload":{PAYLOAD}}}"#);
        match decode_envelope(bytes.as_bytes()).unwrap_err() {
            ProtocolError::UnsupportedVersion { found, supported } => {
                assert_eq!((found.to_string().as_str(), supported), (v, 1));
            }
            other => panic!("v={v}: {other:?}"),
        }
    }
    // A newer version is refused before its shape is read.
    assert!(matches!(
        decode_envelope(br#"{"v":2,"event":{}}"#),
        Err(ProtocolError::UnsupportedVersion { .. })
    ));
    for v in ["1.5", "\"1\"", "null"] {
        let bytes = format!(r#"{{"v":{v},"payload":{PAYLOAD}}}"#);
        assert_eq!(invalid(decode_envelope(bytes.as_bytes()).unwrap_err()), "v");
    }
}

#[test]
fn envelope_needs_its_fields_and_no_others() {
    assert_eq!(
        missing(decode_envelope(format!(r#"{{"payload":{PAYLOAD}}}"#).as_bytes()).unwrap_err()),
        "v"
    );
    assert_eq!(
        missing(decode_envelope(br#"{"v":1}"#).unwrap_err()),
        "payload"
    );
    assert_eq!(
        missing(decode_envelope(br#"{"v":1,"payload":{"session_id":"s"}}"#).unwrap_err()),
        "payload.hook_event_name"
    );
    assert!(matches!(
        decode_envelope(br#"{"v":1,"payload":[]}"#),
        Err(ProtocolError::NotAnObject { field, .. }) if field == "payload"
    ));
    let extra = format!(r#"{{"v":1,"payload":{PAYLOAD},"id":7}}"#);
    assert!(matches!(
        decode_envelope(extra.as_bytes()),
        Err(ProtocolError::ForbiddenField { field }) if field == "id"
    ));
    assert!(matches!(
        decode_envelope(br#"{"hook_event_name":"Stop"}"#),
        Err(ProtocolError::NotAnEnvelope)
    ));
    // The C# port's envelope (`windows/Morrow.Protocol`) is not the contract's.
    assert!(matches!(
        decode_envelope(br#"{"protocolVersion":1,"event":{}}"#),
        Err(ProtocolError::NotAnEnvelope)
    ));
}

#[test]
fn edge_facts_follow_their_schema() {
    let edge = |facts: &str| format!(r#"{{"hook_event_name":"Stop","_edge":{facts}}}"#);
    let cases = [
        (r#"{}"#, "missing", "_edge.v"),
        (r#"{"v":0}"#, "invalid", "_edge.v"),
        (r#"{"v":1,"waits":"yes"}"#, "invalid", "_edge.waits"),
        (
            r#"{"v":1,"stdin_sha256":"xyz"}"#,
            "invalid",
            "_edge.stdin_sha256",
        ),
        (r#"{"v":1,"host":{"name":"n"}}"#, "missing", "_edge.host.id"),
        (r#"{"v":1,"env":{"TMUX":true}}"#, "invalid", "_edge.env"),
    ];
    for (facts, kind, field) in cases {
        let error = decode_envelope(edge(facts).as_bytes()).unwrap_err();
        let got = match kind {
            "missing" => missing(error),
            _ => invalid(error),
        };
        assert_eq!(got, field, "{facts}");
    }
    assert!(matches!(
        decode_envelope(edge(r#"{"v":1,"ppid":12}"#).as_bytes()),
        Err(ProtocolError::ForbiddenField { field }) if field == "_edge.ppid"
    ));
    assert!(matches!(
        decode_envelope(edge("[]").as_bytes()),
        Err(ProtocolError::NotAnObject { field, .. }) if field == "_edge"
    ));
}

#[test]
fn edge_facts_of_another_version_are_read_for_the_fields_known() {
    let bytes = br#"{"_edge":{"v":2,"future":[1],"source":"codex","host":{"id":"h","os":"linux"},"env":{"TMUX":"/tmp/t"}},"prompt":"hi"}"#;
    let decoded = decode_envelope(bytes).unwrap();
    let Envelope::Edge(edge) = &decoded else {
        panic!("not an edge payload")
    };
    let facts = edge.facts();
    assert_eq!(facts.v, 2);
    assert_eq!(facts.source.as_deref(), Some("codex"));
    assert_eq!(facts.other.keys().collect::<Vec<_>>(), ["future"]);
    let host = facts.host.as_ref().unwrap();
    assert_eq!((host.id.as_str(), host.name.as_deref()), ("h", None));
    assert_eq!(host.other.keys().collect::<Vec<_>>(), ["os"]);
    assert_eq!(facts.env.as_ref().unwrap()["TMUX"], "/tmp/t");
    assert_eq!(encode_envelope(&decoded), bytes);
}

#[test]
fn forwarded_payload_with_edge_reads_its_facts() {
    let payload = decode_payload(
        br#"{"hook_event_name":"Stop","session_id":"s","_edge":{"v":1,"waits":false}}"#,
    )
    .unwrap();
    assert_eq!(payload.edge().unwrap().waits, Some(false));
    assert!(matches!(
        decode_payload(br#"{"hook_event_name":"Stop","session_id":"s","_edge":{"v":1,"ppid":1}}"#),
        Err(ProtocolError::ForbiddenField { field }) if field == "_edge.ppid"
    ));
}
