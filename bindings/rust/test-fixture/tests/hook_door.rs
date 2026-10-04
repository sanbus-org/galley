//! The core checks the generation of every node a hook-door read names: from
//! a hook of the second parse, the previous parse's root is refused as a
//! stale tree on every read, and the running parse's own node still reads.
use galley::Session;

extern "C" {
    fn fixture_hook_stale_refusals() -> u32;
    fn fixture_hook_live_reads() -> u32;
}

#[test]
fn a_node_of_an_earlier_parse_is_refused_on_every_hook_door_read() {
    let mut session = Session::new().expect("session");
    session.parse(b"alpha:12").expect("first parse");
    session.parse(b"alpha:12,beta:3").expect("second parse");
    assert_eq!(unsafe { fixture_hook_stale_refusals() }, 13);
    assert_eq!(unsafe { fixture_hook_live_reads() }, 13);
}
