//! The core checks the generation of every node a session-door call names.
use galley::{Error, Session, SessionOptions};

fn two_parses() -> (Session, galley::NodeHandle, galley::NodeHandle) {
    let mut session = Session::new().expect("session");
    session.parse(b"alpha:12").expect("first parse");
    let first = session.root_node().expect("root read").expect("first root");
    session.parse(b"alpha:12,beta:3").expect("second parse");
    let second = session.root_node().expect("root read").expect("second root");
    (session, first, second)
}

#[test]
fn a_handle_of_an_earlier_parse_is_refused_on_every_read() {
    let (session, first, second) = two_parses();
    assert_eq!(session.text(first), Err(Error::StaleTree));
    assert_eq!(session.span(first), Err(Error::StaleTree));
    assert_eq!(session.line_column(first), Err(Error::StaleTree));
    assert_eq!(session.symbol_name(first), Err(Error::StaleTree));
    assert_eq!(session.child_count(first), Err(Error::StaleTree));
    assert_eq!(session.variable_index(first), Err(Error::StaleTree));
    assert_eq!(session.first_child(first), Err(Error::StaleTree));
    assert_eq!(session.parent(first), Err(Error::StaleTree));
    assert!(session.text(second).is_ok());
}

#[test]
fn a_handle_of_an_earlier_parse_is_refused_on_every_edit() {
    let (session, first, second) = two_parses();
    assert_eq!(session.tree_clean_children(first), Err(Error::StaleTree));
    assert_eq!(session.tree_remove_self(first), Err(Error::StaleTree));
    assert_eq!(session.tree_remove_siblings(first, 1), Err(Error::StaleTree));
    assert_eq!(session.tree_remove_children_at(first, 0, 1), Err(Error::StaleTree));
    // A call that names two trees is refused whichever side is stale.
    assert_eq!(session.tree_append_children(first, second), Err(Error::StaleTree));
    assert_eq!(session.tree_append_children(second, first), Err(Error::StaleTree));
    assert_eq!(session.tree_insert_before(second, first), Err(Error::StaleTree));
    assert_eq!(session.tree_insert_after(second, first), Err(Error::StaleTree));
    assert_eq!(session.tree_insert_children_at(second, 0, first), Err(Error::StaleTree));
    // The live tree is untouched by every refusal.
    assert!(session.child_count(second).expect("child count") > 0);
}

// One error is the limit, so a failing parse raises instead of recovering and
// publishes nothing.
fn strict_session() -> Session {
    Session::with_options(SessionOptions {
        max_errors: 1,
        ..SessionOptions::default()
    })
    .expect("session")
}

#[test]
fn a_handle_from_before_a_parse_that_publishes_nothing_is_refused() {
    let mut session = strict_session();
    session.parse(b"alpha:12").expect("first parse");
    let first = session.root_node().expect("root read").expect("root");
    session.parse(b"alpha:").expect_err("syntax error");
    assert_eq!(session.root_node(), Ok(None));
    assert_eq!(session.text(first), Err(Error::StaleTree));
    assert_eq!(session.tree_clean_children(first), Err(Error::StaleTree));
}

// `root_node` keeps "nothing is published" (`Ok(None)`) apart from a
// refusal (`Err`): a fresh session and a session after a parse that published
// nothing both answer `Ok(None)`, and a published tree answers `Ok(Some)`.
#[test]
fn root_node_reports_nothing_published_as_ok_none() {
    let mut session = strict_session();
    assert_eq!(session.root_node(), Ok(None));
    // Nothing published is the core's stale tree, never a zero or an empty snapshot.
    assert_eq!(session.node_count(), Err(Error::StaleTree));
    assert!(matches!(session.snapshot(), Err(Error::StaleTree)));
    session.parse(b"alpha:12").expect("parse");
    assert!(matches!(session.root_node(), Ok(Some(_))));
    session.parse(b"alpha:").expect_err("syntax error");
    assert_eq!(session.root_node(), Ok(None));
    // The position follows the published tree like every read: refused.
    assert_eq!(session.info().map(|_| ()), Err(Error::StaleTree));
}
