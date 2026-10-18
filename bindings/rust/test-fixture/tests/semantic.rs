use galley::{DiagnosticKind, DiagnosticSource, Error, Session};

#[test]
fn out_of_range_values_fail_with_semantic_error() {
    let mut session = Session::new().expect("session");
    let err = session
        .parse(b"alpha:1,beta:2000")
        .expect_err("expected SemanticError");
    assert_eq!(err, Error::Semantic);
    let diagnostic = session
        .diagnostic()
        .expect("diagnostic read")
        .expect("diagnostic");
    assert_eq!(diagnostic.kind, DiagnosticKind::Semantic);
    assert_eq!(
        diagnostic.semantic,
        Some(("Number".to_string(), "value out of range".to_string()))
    );
    // A semantic diagnostic's context chain carries its variable.
    assert_eq!(diagnostic.context, vec!["Number".to_string()]);
    assert_eq!(session.diagnostics().expect("diagnostics").len(), 1);
    assert_eq!(
        session.diagnostic_at(0).expect("first diagnostic").kind,
        DiagnosticKind::Semantic
    );
    // The current and recorded paths read the same diagnostic.
    let current = session
        .diagnostic_snapshot(DiagnosticSource::Current)
        .expect("current snapshot");
    assert_eq!(current.semantic, diagnostic.semantic);
}

#[test]
fn in_range_values_parse_cleanly() {
    let mut session = Session::new().expect("session");
    session.parse(b"alpha:12,beta:3").expect("clean parse");
    assert!(!session.has_diagnostic().expect("probe"));
    assert!(session.diagnostic().expect("diagnostic read").is_none());
    assert!(session.diagnostics().expect("diagnostics").is_empty());
}

#[test]
fn every_snapshot_carries_the_parse_error_totals() {
    let mut session = Session::new().expect("session");

    // Two recovered syntax errors, none semantic: the current and every
    // recorded snapshot report the parse's totals.
    assert_eq!(session.parse(b"alpha:x,beta:y"), Err(Error::Syntax));
    assert_eq!(session.diagnostics().expect("diagnostics").len(), 2);
    let current = session
        .diagnostic()
        .expect("diagnostic read")
        .expect("diagnostic");
    assert_eq!(current.syntax_error_count, 2);
    assert_eq!(current.semantic_error_count, 0);
    for index in 0..2u64 {
        let recorded = session.diagnostic_at(index).expect("recorded diagnostic");
        assert_eq!(recorded.syntax_error_count, 2);
        assert_eq!(recorded.semantic_error_count, 0);
    }

    // One semantic error, no syntax errors.
    assert_eq!(session.parse(b"alpha:1,beta:2000"), Err(Error::Semantic));
    let current = session
        .diagnostic()
        .expect("diagnostic read")
        .expect("diagnostic");
    assert_eq!(current.syntax_error_count, 0);
    assert_eq!(current.semantic_error_count, 1);
    let recorded = session.diagnostic_at(0).expect("recorded diagnostic");
    assert_eq!(recorded.syntax_error_count, 0);
    assert_eq!(recorded.semantic_error_count, 1);
}
