//! Snapshot parity: `Session::snapshot` matches the per-node accessors.
use galley::{Error, NodeHandle, Session, SessionOptions};

fn opt_addr(node: Result<Option<NodeHandle>, Error>) -> u64 {
    node.expect("link")
        .map(|n| n.index())
        .unwrap_or(NodeHandle::INVALID.index())
}

#[test]
fn snapshot_matches_per_node_accessors() {
    let mut session = Session::new().expect("session");
    session.parse_sentinel("alpha:12,beta:3").expect("parse");
    let snap = session.snapshot().expect("snapshot");
    let count = session.node_count().expect("node count") as usize;
    assert_eq!(snap.count as usize, count);
    assert!(count > 0);
    for column in [
        &snap.parent,
        &snap.first_child,
        &snap.next,
        &snap.span_start,
        &snap.span_len,
    ] {
        assert_eq!(column.len(), count);
    }
    assert_eq!(snap.child_count.len(), count);
    assert_eq!(snap.variable.len(), count);
    assert!(snap.variable.contains(&-1));
    assert_eq!(NodeHandle::INVALID.index(), i64::MAX as u64);
    assert_eq!(snap.is_semantic_error.len(), count);
    for address in 0..count as u64 {
        let node = snap.node(address);
        assert_eq!(
            snap.parent[address as usize],
            opt_addr(session.parent(node))
        );
        assert_eq!(
            snap.first_child[address as usize],
            opt_addr(session.first_child(node))
        );
        assert_eq!(
            snap.next[address as usize],
            opt_addr(session.next_sibling(node))
        );
        assert_eq!(
            snap.child_count[address as usize],
            session.child_count(node).expect("child count")
        );
        // "No variable" is -1 in the snapshot's public column and None from
        // the accessor, whatever sentinel the core uses underneath.
        assert_eq!(
            snap.variable[address as usize],
            session
                .variable_index(node)
                .expect("variable index")
                .unwrap_or(-1)
        );
        assert_eq!(
            (
                snap.span_start[address as usize],
                snap.span_len[address as usize]
            ),
            session.span(node).expect("span"),
        );
    }
    // The snapshot alone drives the same preorder walk as the walker.
    let root = session.root_node().expect("root read").expect("root");
    let mut preorder = Vec::new();
    let mut stack = vec![root.index()];
    while let Some(node) = stack.pop() {
        preorder.push(node);
        let mut child = snap.first_child[node as usize];
        let mut chain = Vec::new();
        while child != NodeHandle::INVALID.index() {
            chain.push(child);
            child = snap.next[child as usize];
        }
        assert_eq!(chain.len(), snap.child_count[node as usize] as usize);
        stack.extend(chain.iter().rev());
    }
    let walked: Vec<u64> = session
        .walk(root, false, false)
        .map(|step| step.expect("walk step").node.index())
        .collect();
    assert_eq!(preorder, walked);
    // Spans index last_input.
    let input = session.last_input().expect("last input");
    assert_eq!(input, b"alpha:12,beta:3");
    let root_span = session.span(root).expect("root span");
    assert_eq!(
        &input[root_span.0 as usize..(root_span.0 + root_span.1) as usize],
        b"alpha:12,beta:3"
    );
}

#[test]
fn snapshot_after_a_parse_that_publishes_nothing_refuses() {
    // One error is the limit, so the failing parse raises instead of
    // recovering and publishes nothing.
    let mut session = Session::with_options(SessionOptions {
        max_errors: 1,
        ..SessionOptions::default()
    })
    .expect("session");
    session.parse_sentinel("alpha:12,beta:3").expect("parse");
    session
        .parse_sentinel("gamma:")
        .expect_err("gamma: is a syntax error");
    // The failed parse retired the tree behind the last successful result,
    // and the input with it: both follow the published tree.
    assert_eq!(session.last_input(), Err(Error::StaleTree));
    assert!(matches!(session.snapshot(), Err(Error::StaleTree)));
    assert!(matches!(session.node_count(), Err(Error::StaleTree)));
    assert_eq!(session.root_node(), Ok(None));
    // A successful re-parse reopens the door.
    session.parse_sentinel("alpha:12,beta:3").expect("re-parse");
    let snap = session.snapshot().expect("snapshot");
    assert!(snap.count > 0);
}

// Handles made from a snapshot belong to its parse: a later parse refuses
// them on a read and on an edit.
#[test]
fn snapshot_nodes_go_stale_with_the_next_parse() {
    let mut session = Session::new().expect("session");
    session.parse_sentinel("alpha:12").expect("first parse");
    let snap = session.snapshot().expect("snapshot");
    let node = snap.node(0);
    assert!(!session.text(node).expect("live read").is_empty());
    session.parse_sentinel("alpha:12,beta:3").expect("second parse");
    assert_eq!(session.text(node), Err(Error::StaleTree));
    assert_eq!(session.tree_clean_children(node), Err(Error::StaleTree));
}
