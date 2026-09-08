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
	// The snapshot alone drives the same preorder walk as the walker.
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
	walker, ok := session.Walk(root, false)
	if !ok {
		t.Fatal("expected a walker")
	}
	defer walker.Close()
	var walked []galley.Node
	for {
		step, ok := walker.Next()
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
