//! Snapshot parity: `Session::snapshot` matches the per-node accessors.
use galley_bindings::{NodeHandle, Session};

fn opt_addr(node: Option<NodeHandle>) -> u64 {
    node.map(|n| n.index()).unwrap_or(NodeHandle::INVALID.index())
}

#[test]
fn snapshot_matches_per_node_accessors() {
    let mut session = Session::new().expect("session");
    session.parse_sentinel("alpha:12,beta:3").expect("parse");
    let snap = session.snapshot();
    let count = session.node_count() as usize;
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
    for address in 0..count as u64 {
        let node = NodeHandle::from_index(address);
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
            session.child_count(node)
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
    let root = session.root_node().expect("root");
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
        .walk(root, false)
        .expect("walk")
        .map(|step| step.node.index())
        .collect();
    assert_eq!(preorder, walked);
    // Spans index last_input.
    assert_eq!(session.last_input(), b"alpha:12,beta:3");
    let root_span = session.span(root).expect("root span");
    assert_eq!(
        &session.last_input()[root_span.0 as usize..(root_span.0 + root_span.1) as usize],
        b"alpha:12,beta:3"
    );
}
