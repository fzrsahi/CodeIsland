//! The named pipe's strings (#105). Windows is where they are used, but they are
//! strings, so they are checked here on whatever machine runs the tests.

use morrow_ipc::pipe::{is_sid, pipe_name, security_descriptor};
use morrow_ipc::{EndpointKind, Platform, resolve};

const SID: &str = "S-1-5-21-1004336348-1177238915-682003330-1001";

#[test]
fn the_pipe_name_is_the_one_the_endpoint_rule_gives() {
    let endpoint = resolve(Platform::Windows { sid: SID }, |_| None, |_| false);
    assert_eq!(endpoint.kind(), EndpointKind::NamedPipe);
    assert_eq!(endpoint.as_str(), pipe_name(SID));
    assert_eq!(
        pipe_name(SID),
        r"\\.\pipe\morrow-S-1-5-21-1004336348-1177238915-682003330-1001"
    );
}

#[test]
fn a_sid_is_mapped_the_way_the_rule_maps_it() {
    // Anything outside `[A-Za-z0-9]` becomes `-`, in both places, so the hook
    // and the island cannot disagree about the name.
    let odd = "S-1-5-21-1.2:3";
    assert_eq!(
        pipe_name(odd),
        r"\\.\pipe\morrow-S-1-5-21-1-2-3",
        "the rule's mapping, applied here too"
    );
}

#[test]
fn the_descriptor_names_only_this_user() {
    let descriptor = security_descriptor(SID);
    assert_eq!(
        descriptor,
        "O:S-1-5-21-1004336348-1177238915-682003330-1001\
         G:S-1-5-21-1004336348-1177238915-682003330-1001\
         D:(A;;GA;;;S-1-5-21-1004336348-1177238915-682003330-1001)"
    );
    // The two ACEs that would widen it to everyone or to anonymous logons.
    assert!(!descriptor.contains(";;;WD)"), "{descriptor}");
    assert!(!descriptor.contains(";;;AN)"), "{descriptor}");
    assert!(!descriptor.contains("(OI)"), "{descriptor}");
    assert!(!descriptor.contains("(CI)"), "{descriptor}");
}

#[test]
fn a_sid_that_is_not_one_is_caught_before_an_api_sees_it() {
    assert!(is_sid(SID));
    assert!(is_sid("S-1-5-18"));
    assert!(!is_sid(""), "empty would build `D:(A;;GA;;;)`: everyone");
    assert!(!is_sid("S-1-"), "no components");
    assert!(!is_sid("S-2-5-21"), "not a Windows SID");
    assert!(!is_sid("S-1-5-21-x"), "not decimal");
    assert!(!is_sid("S-1-5-21-1)"), "an ACE cannot be closed early");
}
