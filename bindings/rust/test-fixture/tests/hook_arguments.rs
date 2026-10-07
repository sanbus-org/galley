//! The core checks every `galley_procedure_*` call: the arguments of a hook
//! that has returned are refused with `Error::StaleHook`, from a later hook
//! of the same parse and after the parse alike.
use galley::{Error, Session};

extern "C" {
    fn fixture_stale_hook_during() -> u32;
    fn fixture_stale_hook_after() -> u32;
    fn fixture_forget_first_pair();
}

// One test, in order: the fixture records the first Pair hook in process-wide
// state, so two parsing tests running side by side would record each other's.
#[test]
fn the_core_refuses_returned_hooks_and_nodes_of_two_parses() {
    unsafe { fixture_forget_first_pair() };
    let mut session = Session::new().expect("session");
    session.parse(b"alpha:12,beta:3").expect("parse");
    assert_eq!(unsafe { fixture_stale_hook_during() }, 9);
    assert_eq!(unsafe { fixture_stale_hook_after() }, 9);

    // An edit given nodes of two parses is refused, whichever is the live one.
    let mut session = Session::new().expect("session");
    session.parse(b"alpha:12,beta:3").expect("first parse");
    let old_root = session.root_node().expect("root").expect("a root");
    let detached = session
        .tree_clean_children(old_root)
        .expect("clean")
        .expect("children");
    session.parse(b"alpha:12,beta:3").expect("second parse");
    let fresh_root = session.root_node().expect("root").expect("a root");
    assert_eq!(
        session.tree_append_children(fresh_root, detached),
        Err(Error::StaleTree)
    );
    assert_eq!(
        session.tree_insert_before(fresh_root, detached),
        Err(Error::StaleTree)
    );
    assert_eq!(
        session.tree_insert_after(fresh_root, detached),
        Err(Error::StaleTree)
    );
    assert_eq!(
        session.tree_insert_children_at(fresh_root, 0, detached),
        Err(Error::StaleTree)
    );
    assert_eq!(
        session.tree_append_children(detached, fresh_root),
        Err(Error::StaleTree)
    );
}
