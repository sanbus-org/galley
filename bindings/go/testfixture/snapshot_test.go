package testfixture

import (
	"bytes"
	"testing"

	galley "github.com/sanbus-org/galley/bindings/go/testfixture/galley"
)

func wantLink(node galley.Node, ok bool) galley.Node {
	if !ok {
		return galley.InvalidNode
	}
	return node
}

func TestSnapshotMatchesPerNodeAccessors(t *testing.T) {
	session, root := walkSession(t, "alpha:12,beta:3")
	snap, err := session.Snapshot()
	if err != nil {
		t.Fatalf("snapshot: %v", err)
	}
	count := session.NodeCount()
	if snap.Count != count {
		t.Fatalf("snapshot count %d, node count %d", snap.Count, count)
	}
	if count == 0 {
		t.Fatal("expected nodes")
	}
	columns := map[string]int{
		"parent": len(snap.Parent), "firstChild": len(snap.FirstChild),
		"next": len(snap.Next), "childCount": len(snap.ChildCount),
		"variable": len(snap.Variable), "spanStart": len(snap.SpanStart),
		"spanLen": len(snap.SpanLen),
	}
	for name, length := range columns {
		if uint64(length) != count {
			t.Fatalf("snapshot column %s has %d entries, want %d", name, length, count)
		}
	}
	for address := uint64(0); address < count; address++ {
		node := galley.Node(address)
		parent, ok := session.Parent(node)
		if snap.Parent[address] != wantLink(parent, ok) {
			t.Fatalf("node %d: parent %d, want %d", address, snap.Parent[address], wantLink(parent, ok))
		}
		first, ok := session.FirstChild(node)
		if snap.FirstChild[address] != wantLink(first, ok) {
			t.Fatalf("node %d: firstChild mismatch", address)
		}
		next, ok := session.NextSibling(node)
		if snap.Next[address] != wantLink(next, ok) {
			t.Fatalf("node %d: next mismatch", address)
		}
		if snap.ChildCount[address] != session.ChildCount(node) {
			t.Fatalf("node %d: childCount mismatch", address)
		}
		if snap.Variable[address] < -1 {
			t.Fatalf("node %d: variable %d", address, snap.Variable[address])
		}
		start, length, ok := session.Span(node)
		if !ok {
			t.Fatalf("node %d: no span", address)
		}
		if snap.SpanStart[address] != start || snap.SpanLen[address] != length {
			t.Fatalf("node %d: span mismatch", address)
		}
	}
	var preorder []galley.Node
	stack := []galley.Node{root}
	for len(stack) > 0 {
		node := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		preorder = append(preorder, node)
		var chain []galley.Node
		for child := snap.FirstChild[node]; child != galley.InvalidNode; child = snap.Next[child] {
			chain = append(chain, child)
		}
		if uint32(len(chain)) != snap.ChildCount[node] {
			t.Fatalf("node %d: %d chained children, count says %d", node, len(chain), snap.ChildCount[node])
		}
		for i := len(chain) - 1; i >= 0; i-- {
			stack = append(stack, chain[i])
		}
	}
	walker := session.Walk(root, false)
	var walked []galley.Node
	for {
		step, ok, err := walker.Next()
		if err != nil {
			t.Fatalf("walk step: %v", err)
		}
		if !ok {
			break
		}
		walked = append(walked, step.Node)
	}
	if len(walked) != len(preorder) {
		t.Fatalf("walker visited %d nodes, snapshot %d", len(walked), len(preorder))
	}
	for i := range preorder {
		if walked[i] != preorder[i] {
			t.Fatalf("step %d: walker %d, snapshot %d", i, walked[i], preorder[i])
		}
	}
	// Spans index LastInput.
	if input := session.LastInput(); !bytes.Equal(input, []byte("alpha:12,beta:3")) {
		t.Fatalf("last input %q", input)
	}
}

// A failed parse resets node storage behind the last successful result:
// Snapshot must answer ErrInvalidNode through the gate — even at count 0,
// where NodeCount() reports the natural zero — instead of an empty
// success, and the retained input must survive until a successful
// re-parse reopens the door.
func TestSnapshotAfterFailedParseRefuses(t *testing.T) {
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(session.Close)
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("parse: %v", err)
	}
	if _, err := session.Parse([]byte("gamma:")); err == nil {
		t.Fatal("expected a syntax error for gamma:")
	}
	if input := session.LastInput(); !bytes.Equal(input, []byte("alpha:12,beta:3")) {
		t.Fatalf("last input %q, want the last successful parse", input)
	}
	if snap, err := session.Snapshot(); err != galley.ErrInvalidNode || snap.Count != 0 {
		t.Fatalf("snapshot after failed parse = (count %d, %v), want count 0 and ErrInvalidNode", snap.Count, err)
	}
	if text, ok := session.Text(galley.Node(0)); ok {
		t.Fatalf("text after failed parse = (%q, %v), want no value", text, ok)
	}
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("re-parse: %v", err)
	}
	snap, err := session.Snapshot()
	if err != nil {
		t.Fatalf("snapshot after re-parse: %v", err)
	}
	if snap.Count == 0 {
		t.Fatal("expected nodes after a successful re-parse")
	}
}
