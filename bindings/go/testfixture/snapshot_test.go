package testfixture

import (
	"bytes"
	"testing"

	galley "github.com/sanbus-org/galley/bindings/go/testfixture/galley"
)

func wantLink(t *testing.T, node galley.Node, ok bool, err error) uint64 {
	t.Helper()
	if err != nil {
		t.Fatalf("link: %v", err)
	}
	if !ok {
		return galley.InvalidNode.Index()
	}
	return node.Index()
}

func TestSnapshotMatchesPerNodeAccessors(t *testing.T) {
	session, root := walkSession(t, "alpha:12,beta:3")
	snap, err := session.Snapshot()
	if err != nil {
		t.Fatalf("snapshot: %v", err)
	}
	count, err := session.NodeCount()
	if err != nil {
		t.Fatalf("node count: %v", err)
	}
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
	withoutVariable := 0
	for address := uint64(0); address < count; address++ {
		node := snap.Node(address)
		parent, ok, err := session.Parent(node)
		if want := wantLink(t, parent, ok, err); snap.Parent[address] != want {
			t.Fatalf("node %d: parent %d, want %d", address, snap.Parent[address], want)
		}
		first, ok, err := session.FirstChild(node)
		if snap.FirstChild[address] != wantLink(t, first, ok, err) {
			t.Fatalf("node %d: firstChild mismatch", address)
		}
		next, ok, err := session.NextSibling(node)
		if snap.Next[address] != wantLink(t, next, ok, err) {
			t.Fatalf("node %d: next mismatch", address)
		}
		childCount, err := session.ChildCount(node)
		if err != nil || snap.ChildCount[address] != childCount {
			t.Fatalf("node %d: childCount mismatch (%d, %v)", address, childCount, err)
		}
		if snap.Variable[address] < -1 {
			t.Fatalf("node %d: variable %d", address, snap.Variable[address])
		}
		if snap.Variable[address] == -1 {
			withoutVariable++
		}
		start, length, err := session.Span(node)
		if err != nil {
			t.Fatalf("node %d: no span: %v", address, err)
		}
		if snap.SpanStart[address] != start || snap.SpanLen[address] != length {
			t.Fatalf("node %d: span mismatch", address)
		}
	}
	if withoutVariable == 0 {
		t.Fatal("expected a node without a variable to read -1")
	}
	if galley.InvalidNode.Index() != 1<<63-1 {
		t.Fatalf("invalid node sentinel %#x, want INT64_MAX", galley.InvalidNode.Index())
	}
	var preorder []uint64
	stack := []uint64{root.Index()}
	for len(stack) > 0 {
		node := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		preorder = append(preorder, node)
		var chain []uint64
		for child := snap.FirstChild[node]; child != galley.InvalidNode.Index(); child = snap.Next[child] {
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
	var walked []uint64
	for {
		step, ok, err := walker.Next()
		if err != nil {
			t.Fatalf("walk step: %v", err)
		}
		if !ok {
			break
		}
		walked = append(walked, step.Node.Index())
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
	if input, err := session.LastInput(); err != nil || !bytes.Equal(input, []byte("alpha:12,beta:3")) {
		t.Fatalf("last input %q, %v", input, err)
	}
}

// A parse that publishes nothing resets node storage behind the last
// successful result: Snapshot must answer ErrStaleTree through the gate —
// even at count 0, where NodeCount() reports the natural zero — instead of
// an empty success, and LastInput follows the published tree, so it is
// refused too until a successful re-parse reopens the door. One error is the
// limit, so the failing parse raises instead of recovering.
func TestSnapshotAfterAParseThatPublishesNothingRefuses(t *testing.T) {
	options := galley.DefaultOptions()
	options.MaxErrors = 1
	session, err := galley.WithOptions(options)
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("parse: %v", err)
	}
	root, ok, err := session.RootNode()
	if err != nil || !ok {
		t.Fatalf("root = (ok %v, %v), want a root", ok, err)
	}
	if _, err := session.Parse([]byte("gamma:")); err == nil {
		t.Fatal("expected a syntax error for gamma:")
	}
	if input, err := session.LastInput(); err != galley.ErrStaleTree || input != nil {
		t.Fatalf("last input = (%q, %v), want (nil, ErrStaleTree)", input, err)
	}
	if snap, err := session.Snapshot(); err != galley.ErrStaleTree || snap.Count != 0 {
		t.Fatalf("snapshot after failed parse = (count %d, %v), want count 0 and ErrStaleTree", snap.Count, err)
	}
	if _, err := session.NodeCount(); err != galley.ErrStaleTree {
		t.Fatalf("node count after failed parse = %v, want ErrStaleTree", err)
	}
	if _, ok, err := session.RootNode(); ok || err != nil {
		t.Fatalf("root after failed parse = (ok %v, %v), want (false, nil)", ok, err)
	}
	// A node of the parse the failed one replaced is refused on a read and an edit.
	if _, err := session.Text(root); err != galley.ErrStaleTree {
		t.Fatalf("text after failed parse = %v, want ErrStaleTree", err)
	}
	if _, _, err := session.TreeCleanChildren(root); err != galley.ErrStaleTree {
		t.Fatalf("edit after failed parse = %v, want ErrStaleTree", err)
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

// A node made from a snapshot belongs to its parse: a later parse refuses it
// on a read and on an edit.
func TestSnapshotNodesGoStaleWithTheNextParse(t *testing.T) {
	session, _ := walkSession(t, "alpha:12")
	snap, err := session.Snapshot()
	if err != nil {
		t.Fatalf("snapshot: %v", err)
	}
	node := snap.Node(0)
	if _, err := session.Text(node); err != nil {
		t.Fatalf("live read: %v", err)
	}
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("second parse: %v", err)
	}
	if _, err := session.Text(node); err != galley.ErrStaleTree {
		t.Fatalf("read after re-parse = %v, want ErrStaleTree", err)
	}
	if _, _, err := session.TreeCleanChildren(node); err != galley.ErrStaleTree {
		t.Fatalf("edit after re-parse = %v, want ErrStaleTree", err)
	}
}
