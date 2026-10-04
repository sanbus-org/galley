use galley::Session;

fn hand_rolled(session: &Session, root: galley::NodeHandle) -> Vec<(galley::NodeHandle, u32)> {
    fn recurse(
        session: &Session,
        node: galley::NodeHandle,
        depth: u32,
        out: &mut Vec<(galley::NodeHandle, u32)>,
    ) {
        out.push((node, depth));
        let mut child = session.first_child(node).expect("first child");
        while let Some(current) = child {
            recurse(session, current, depth + 1, out);
            child = session.next_sibling(current).expect("next sibling");
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
    let root = session.root_node().expect("root read").expect("root");
    let walked: Vec<(galley::NodeHandle, u32)> = session
        .walk(root, false, false)
        .map(|step| step.expect("walk step"))
        .map(|step| (step.node, step.depth))
        .collect();
    let expected = hand_rolled(&session, root);
    assert!(walked.len() > 1);
    assert_eq!(walked, expected);
    assert!(!session
        .walk(root, false, false)
        .map(|step| step.expect("walk step"))
        .any(|step| step.is_semantic_error));
}

#[test]
fn walk_skip_children_prunes_subtree() {
    let mut session = Session::new().expect("session");
    session.parse(b"alpha:12,beta:3").expect("clean parse");
    let root = session.root_node().expect("root read").expect("root");
    let mut walker = session.walk(root, false, false);
    let first = walker.next().expect("first step").expect("first step");
    assert_eq!(first.node, root);
    assert_eq!(first.depth, 0);
    walker.skip_children();
    assert!(walker.next().is_none());
}

// walk() hands back a walker for any root; the failure lands at the first
// step. The sentinel belongs to no parse, so the core reports a stale tree.
#[test]
fn walk_of_the_invalid_sentinel_fails_at_the_first_step() {
    let mut session = Session::new().expect("session");
    session.parse(b"alpha:12,beta:3").expect("clean parse");
    let mut walker = session.walk(galley::NodeHandle::INVALID, false, false);
    assert_eq!(walker.next(), Some(Err(galley::Error::StaleTree)));
    // The failure ends the walk rather than repeating.
    assert!(walker.next().is_none());
}

// A walker made from a parse-1 handle refuses at its first step once a
// second parse has published.
#[test]
fn walk_of_a_stale_root_fails_at_the_first_step() {
    let mut session = Session::new().expect("session");
    session.parse(b"alpha:12").expect("first parse");
    let stale = session.root_node().expect("root read").expect("root");
    session.parse(b"alpha:12,beta:3").expect("second parse");
    let mut walker = session.walk(stale, false, false);
    assert_eq!(walker.next(), Some(Err(galley::Error::StaleTree)));
    assert!(walker.next().is_none());
}
