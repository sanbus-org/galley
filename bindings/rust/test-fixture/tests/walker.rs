use galley::Session;

fn hand_rolled(
    session: &Session,
    root: galley::NodeHandle,
) -> Vec<(galley::NodeHandle, u32)> {
    fn recurse(
        session: &Session,
        node: galley::NodeHandle,
        depth: u32,
        out: &mut Vec<(galley::NodeHandle, u32)>,
    ) {
        out.push((node, depth));
        let mut child = session.first_child(node);
        while let Some(current) = child {
            recurse(session, current, depth + 1, out);
            child = session.next_sibling(current);
        }
    }
    let mut visited = Vec::new();
    recurse(session, root, 0, &mut visited);
    visited
}

#[test]
fn walk_matches_hand_rolled_recursion() {
    let mut session = Session::new().expect("session");
    session.parse(b"alpha:12,beta:3").expect("clean parse");
    let root = session.root_node().expect("root");
    let walked: Vec<(galley::NodeHandle, u32)> = session
        .walk(root, false)
        .expect("walker")
        .map(|step| (step.node, step.depth))
        .collect();
    let expected = hand_rolled(&session, root);
    assert!(walked.len() > 1);
    assert_eq!(walked, expected);
    assert!(!session
        .walk(root, false)
        .expect("walker")
        .any(|step| step.is_semantic_error));
}

#[test]
fn walk_skip_children_prunes_subtree() {
    let mut session = Session::new().expect("session");
    session.parse(b"alpha:12,beta:3").expect("clean parse");
    let root = session.root_node().expect("root");
    let mut walker = session.walk(root, false).expect("walker");
    let first = walker.next().expect("first step");
    assert_eq!(first.node, root);
    assert_eq!(first.depth, 0);
    walker.skip_children();
    assert!(walker.next().is_none());
    assert!(session
        .walk(galley::NodeHandle::INVALID, false)
        .is_none());
}
