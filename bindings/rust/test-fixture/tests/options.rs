//! The options object: unset options stay unset, set options reach the core,
//! and a session opened either way parses.
use galley::{Error, Session, SessionOptions};

const SAMPLE: &str = "alpha:12,beta:3";

#[test]
fn default_options_leave_every_option_unset() {
    let options = SessionOptions::default();
    assert_eq!(options.max_errors, None);
    assert_eq!(options.recovery_window, None);
    assert_eq!(options.stack_overflow_recovery, None);
    assert_eq!(options.syntax_error_stack_depth, None);
    assert!(options.message_overrides.is_empty());
}

// An unset option makes no setter call and keeps its core default; the
// session still opens and parses.
#[test]
fn a_session_from_default_options_parses() {
    let mut session = Session::with_options(SessionOptions::default()).expect("session");
    assert_eq!(session.parse(SAMPLE.as_bytes()), Ok(SAMPLE.len()));
    assert!(session.root_node().expect("root read").is_some());
}

// Every option set to an in-domain value reaches its setter; the session
// opens and parses with them all held.
#[test]
fn a_session_from_explicit_options_parses() {
    let mut session = Session::with_options(SessionOptions {
        max_errors: Some(1),
        recovery_window: Some(1),
        stack_overflow_recovery: Some(false),
        syntax_error_stack_depth: Some(4),
        ..Default::default()
    })
    .expect("session");
    assert_eq!(session.parse(SAMPLE.as_bytes()), Ok(SAMPLE.len()));
    assert!(session.root_node().expect("root read").is_some());
    // A limit of one error is strict: the failing parse publishes nothing,
    // so the held value reached the core.
    assert_eq!(session.parse(b"alpha:"), Err(Error::Syntax));
    assert_eq!(session.root_node(), Ok(None));
}
