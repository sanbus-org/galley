//! A parse that fails after running to its end publishes its tree: semantic
//! errors mark nodes, recovered syntax errors leave flagged nodes over the
//! damaged input, and `parse` still raises. A parse the parser cannot recover
//! from publishes nothing.
use galley::{Error, Session, SessionOptions, WalkStep};

/// Recovery skips `x,beta:` to resynchronize, then `2`: two recovered nodes.
const RECOVERED: &str = "alpha:x,beta:2";
/// Parses, but a hook reports one semantic error on the Number `2000`.
const SEMANTIC: &str = "alpha:1,beta:2000";

// One error is the limit, so a failing parse raises instead of recovering and
// publishes nothing.
fn strict_session() -> Session {
    Session::with_options(SessionOptions {
        max_errors: 1,
        ..SessionOptions::default()
    })
    .expect("session")
}

fn steps(session: &Session, skip_semantic_errors: bool, skip_recovered: bool) -> Vec<(String, u64, u64, WalkStep)> {
    let root = session.root_node().expect("root read").expect("root");
    session
        .walk(root, skip_semantic_errors, skip_recovered)
        .map(|step| step.expect("walk step"))
        .map(|step| {
            let (start, length) = session.span(step.node).expect("span");
            let symbol = String::from_utf8_lossy(session.symbol_name(step.node).expect("symbol name")).into_owned();
            (symbol, start, length, step)
        })
        .collect()
}

#[test]
fn a_semantic_only_failure_publishes_its_tree() {
    let mut session = Session::new().expect("session");
    assert_eq!(session.parse(SEMANTIC.as_bytes()), Err(Error::Semantic));

    let full = steps(&session, false, false);
    let marked: Vec<_> = full.iter().filter(|(_, _, _, step)| step.is_semantic_error).collect();
    assert_eq!(marked.len(), 1);
    assert_eq!((marked[0].0.as_str(), marked[0].1, marked[0].2), ("Number", 13, 4));
    assert!(full.iter().all(|(_, _, _, step)| !step.is_recovered));

    let pruned = steps(&session, true, false);
    assert!(pruned.len() < full.len());
    assert!(pruned.iter().all(|(_, _, _, step)| !step.is_semantic_error));
    // Nothing is recovered here, so skipping recovered nodes changes nothing.
    assert_eq!(steps(&session, false, true).len(), full.len());

    let snapshot = session.snapshot().expect("snapshot");
    assert_eq!(snapshot.is_semantic_error.iter().filter(|flag| **flag).count(), 1);
    assert!(snapshot.is_recovered.iter().all(|flag| !flag));

    assert_eq!(session.last_input().expect("last input"), SEMANTIC.as_bytes());
    assert!(session.info().expect("info").is_some());

    // The next parse retires the errored tree's nodes.
    let stale = session.root_node().expect("root read").expect("root");
    session.parse(b"alpha:12,beta:3").expect("clean parse");
    assert_eq!(session.text(stale), Err(Error::StaleTree));
}

#[test]
fn a_recovered_syntax_error_publishes_its_tree() {
    let mut session = Session::new().expect("session");
    assert_eq!(session.parse(RECOVERED.as_bytes()), Err(Error::Syntax));

    let full = steps(&session, false, false);
    let recovered: Vec<_> = full.iter().filter(|(_, _, _, step)| step.is_recovered).collect();
    assert_eq!(recovered.len(), 2);
    assert!(full.iter().all(|(_, _, _, step)| !step.is_semantic_error));
    // The damaged Number covers the input recovery skipped: `x,beta:`.
    assert_eq!((recovered[0].0.as_str(), recovered[0].1, recovered[0].2), ("Number", 6, 7));

    // Skipping them leaves only undamaged nodes, none inside the damage.
    let undamaged = steps(&session, false, true);
    assert_eq!(undamaged.len(), full.len() - 2);
    assert!(undamaged.iter().all(|(_, start, _, step)| !step.is_recovered && (*start < 6 || *start >= 13)));

    // The snapshot column reads what the walk reports, node for node.
    let snapshot = session.snapshot().expect("snapshot");
    let flagged: Vec<u64> = (0..snapshot.count).filter(|i| snapshot.is_recovered[*i as usize]).collect();
    let walked: Vec<u64> = full.iter().filter(|(_, _, _, step)| step.is_recovered).map(|(_, _, _, step)| step.node.index()).collect();
    assert_eq!(flagged, walked);

    assert_eq!(session.last_input().expect("last input"), RECOVERED.as_bytes());
    assert!(session.info().expect("info").is_some());

    let stale = session.root_node().expect("root read").expect("root");
    session.parse(b"alpha:12,beta:3").expect("clean parse");
    assert_eq!(session.text(stale), Err(Error::StaleTree));
    assert!(session.walk(stale, false, false).next().expect("a step").is_err());
}

#[test]
fn an_unrecovered_syntax_error_publishes_nothing() {
    let mut session = strict_session();
    assert_eq!(session.parse(RECOVERED.as_bytes()), Err(Error::Syntax));
    assert_eq!(session.root_node(), Ok(None));
    assert_eq!(session.last_input(), Err(Error::StaleTree));
    assert_eq!(session.info().map(|_| ()), Err(Error::StaleTree));
    assert!(matches!(session.snapshot(), Err(Error::StaleTree)));
}

#[test]
fn last_input_and_info_refuse_before_any_parse() {
    let session = Session::new().expect("session");
    assert_eq!(session.last_input(), Err(Error::StaleTree));
    assert_eq!(session.info().map(|_| ()), Err(Error::StaleTree));
}

#[test]
fn a_failure_without_a_root_still_publishes_its_input() {
    // Recovery skips all of the input before the grammar's first symbol: the
    // parse publishes, but there is no tree to hold a root.
    let mut session = Session::new().expect("session");
    assert_eq!(session.parse(b"?"), Err(Error::Syntax));
    assert_eq!(session.root_node(), Ok(None));
    assert_eq!(session.last_input().expect("last input"), b"?");
}
