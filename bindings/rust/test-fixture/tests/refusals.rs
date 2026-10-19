//! The frozen C ABI refuses misuse with a status, and a refusal never
//! answers like a real one: the safe wrappers raise it, an out-parameter
//! stays untouched, and an index past its table reads as the refusal status
//! — `out of range`, `invalid argument`, or `no diagnostic available`.
use galley::{DiagnosticKind, Error, Session, SessionOptions};
use std::ffi::{c_char, c_void};

// Raw declarations for the out-parameter checks the safe wrappers hide. The
// test binary links the fixture's `libgalley-rust`.
extern "C" {
    fn galley_has_diagnostic(session: *mut c_void, out_has: *mut i32) -> i64;
    fn galley_stack_overflow_recovery_available() -> i32;
    fn galley_hooks_name(index: usize, out_data: *mut *const c_char, out_len: *mut usize) -> i64;
    fn galley_symbol_name(
        session: *mut c_void,
        index: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_symbol_is_terminal(
        session: *mut c_void,
        index: u64,
        out_is_terminal: *mut i32,
    ) -> i64;
    fn galley_variable_name(
        session: *mut c_void,
        index: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
}

const NULL_SESSION: *mut c_void = std::ptr::null_mut();

#[test]
fn a_named_status_renders_the_library_text() {
    assert!(Error::Syntax.description().contains("syntax"));
}

// The options setters are the entire gate: a value outside its option's
// domain comes back through the public API as `invalid argument`, before any
// session exists. Enabling stack-overflow recovery is out of its domain only
// where the platform reports it unsupported.
#[test]
fn out_of_domain_options_fail_with_invalid_argument() {
    let mut refused = vec![
        SessionOptions {
            max_errors: Some(0),
            ..Default::default()
        },
        SessionOptions {
            max_errors: Some(-1),
            ..Default::default()
        },
        SessionOptions {
            recovery_window: Some(0),
            ..Default::default()
        },
        SessionOptions {
            recovery_window: Some(-1),
            ..Default::default()
        },
        SessionOptions {
            syntax_error_stack_depth: Some(65),
            ..Default::default()
        },
    ];
    if unsafe { galley_stack_overflow_recovery_available() } == 0 {
        refused.push(SessionOptions {
            stack_overflow_recovery: Some(true),
            ..Default::default()
        });
    }
    for options in refused {
        assert_eq!(
            Session::with_options(options).map(drop),
            Err(Error::InvalidArgument)
        );
    }
}

#[test]
fn hook_names_are_refused_past_the_table_and_leave_outs_untouched() {
    // The fixture binds compiled Rust hooks, so it forwards none to a host.
    assert_eq!(galley::hooks_count(), 0);
    assert_eq!(galley::hooks_name(0), Err(Error::OutOfRange));
    let mut data: *const c_char = std::ptr::null();
    let mut len = usize::MAX;
    assert_eq!(unsafe { galley_hooks_name(0, &mut data, &mut len) }, -17);
    assert!(data.is_null());
    assert_eq!(len, usize::MAX);
}

#[test]
fn grammar_table_indexes_are_refused_past_their_counts() {
    let session = Session::new().expect("session");
    assert!(galley::symbol_count() > 0);
    assert!(!session.symbol_name_at(0).expect("first symbol").is_empty());
    assert_eq!(
        session.symbol_name_at(galley::symbol_count()),
        Err(Error::OutOfRange)
    );
    assert_eq!(
        session.symbol_is_terminal(galley::symbol_count()),
        Err(Error::OutOfRange)
    );
    assert!(session.symbol_is_terminal(0).is_ok());
    assert!(galley::variable_count() > 0);
    assert!(!session
        .variable_name_at(0)
        .expect("first variable")
        .is_empty());
    assert_eq!(
        session.variable_name_at(galley::variable_count()),
        Err(Error::OutOfRange)
    );
}

#[test]
fn a_null_session_refuses_every_table_read_without_touching_outs() {
    let mut data: *const c_char = std::ptr::null();
    let mut len = usize::MAX;
    assert_eq!(
        unsafe { galley_symbol_name(NULL_SESSION, 0, &mut data, &mut len) },
        -1
    );
    assert!(data.is_null());
    assert_eq!(len, usize::MAX);

    let mut is_terminal = -1i32;
    assert_eq!(
        unsafe { galley_symbol_is_terminal(NULL_SESSION, 0, &mut is_terminal) },
        -1
    );
    assert_eq!(is_terminal, -1);

    let mut data: *const c_char = std::ptr::null();
    let mut len = usize::MAX;
    assert_eq!(
        unsafe { galley_variable_name(NULL_SESSION, 0, &mut data, &mut len) },
        -1
    );
    assert!(data.is_null());
    assert_eq!(len, usize::MAX);

    let mut has = -1i32;
    assert_eq!(unsafe { galley_has_diagnostic(NULL_SESSION, &mut has) }, -1);
    assert_eq!(has, -1);
}

#[test]
fn a_recorded_index_past_the_records_is_no_diagnostic() {
    let mut session = Session::new().expect("session");
    // One recovered syntax error records one diagnostic.
    assert_eq!(session.parse(b"alpha:"), Err(Error::Syntax));
    assert!(session.has_diagnostic().expect("probe"));
    assert_eq!(
        session.diagnostic_at(0).expect("first diagnostic").kind,
        DiagnosticKind::Syntax
    );
    assert_eq!(session.diagnostic_at(1).unwrap_err(), Error::NoDiagnostic);
    assert_eq!(
        session
            .diagnostic_snapshot(galley::DiagnosticSource::Recorded(1))
            .unwrap_err(),
        Error::NoDiagnostic
    );
    assert_eq!(session.diagnostics().expect("diagnostics").len(), 1);
}
