use galley::{DiagnosticKind, Error, Session};

#[test]
fn out_of_range_values_fail_with_semantic_error() {
    let mut session = Session::new().expect("session");
    let err = session
        .parse(b"alpha:1,beta:2000")
        .expect_err("expected SemanticError");
    assert_eq!(err, Error::Semantic);
    let diagnostic = session.diagnostic().expect("diagnostic");
    assert_eq!(diagnostic.kind, DiagnosticKind::Semantic);
    assert_eq!(
        diagnostic.semantic,
        Some(("Number".to_string(), "value out of range".to_string()))
    );
    assert_eq!(session.diagnostics().len(), 1);
}

#[test]
fn in_range_values_parse_cleanly() {
    let mut session = Session::new().expect("session");
    session.parse(b"alpha:12,beta:3").expect("clean parse");
    assert!(session.diagnostic().is_none());
}
