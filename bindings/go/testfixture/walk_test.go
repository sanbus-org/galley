package testfixture

import (
	"testing"

	galley "github.com/sanbus-org/galley/bindings/go/testfixture/galley"
)

func walkSession(t *testing.T, input string) (*galley.Session, galley.Node) {
	t.Helper()
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })
	if _, err := session.Parse([]byte(input)); err != nil {
		t.Fatalf("parse: %v", err)
	}
	root, ok, err := session.RootNode()
	if err != nil || !ok {
		t.Fatal("expected a root node")
	}
	return session, root
}

func TestWalkMatchesHandRolledRecursion(t *testing.T) {
	session, root := walkSession(t, "alpha:12,beta:3")

	type visit struct {
		node  galley.Node
		depth uint32
	}
	var expected []visit
	var recurse func(node galley.Node, depth uint32)
	recurse = func(node galley.Node, depth uint32) {
		expected = append(expected, visit{node, depth})
		children, err := session.Children(node)
		if err != nil {
			t.Fatalf("children: %v", err)
		}
		for _, child := range children {
			recurse(child, depth+1)
		}
	}
	recurse(root, 0)
	if len(expected) <= 1 {
		t.Fatalf("expected a nested tree, got %d nodes", len(expected))
	}

	walker := session.Walk(root, false)
	var walked []visit
	for {
		step, ok, err := walker.Next()
		if err != nil {
			t.Fatalf("walk step: %v", err)
		}
		if !ok {
			break
		}
		if step.IsSemanticError {
			t.Fatal("clean tree must not flag semantic errors")
		}
		walked = append(walked, visit{step.Node, step.Depth})
	}
	if len(walked) != len(expected) {
		t.Fatalf("walker visited %d nodes, recursion %d", len(walked), len(expected))
	}
	for i := range expected {
		if walked[i] != expected[i] {
			t.Fatalf("step %d: walker %+v, recursion %+v", i, walked[i], expected[i])
		}
	}
}

func TestWalkSkipChildrenPrunesSubtree(t *testing.T) {
	session, root := walkSession(t, "alpha:12,beta:3")
	walker := session.Walk(root, false)
	first, ok, err := walker.Next()
	if err != nil {
		t.Fatalf("walk step: %v", err)
	}
	if !ok || first.Node != root || first.Depth != 0 {
		t.Fatalf("expected the root first, got %+v", first)
	}
	walker.SkipChildren()
	if _, ok, err := walker.Next(); ok || err != nil {
		t.Fatalf("expected the walk to end after pruning the root, ok=%v err=%v", ok, err)
	}
	// Nothing is refused at creation: the sentinel belongs to no parse, so a
	// walker over it fails at its first step with a stale tree.
	invalid := session.Walk(galley.InvalidNode, false)
	if _, ok, err := invalid.Next(); ok || err != galley.ErrStaleTree {
		t.Fatalf("expected ErrStaleTree at the first step, ok=%v err=%v", ok, err)
	}
}

// A walker over a parse-1 root refuses at its first step once a second parse
// has published.
func TestWalkOfAStaleRootFailsAtTheFirstStep(t *testing.T) {
	session, stale := walkSession(t, "alpha:12")
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("second parse: %v", err)
	}
	walker := session.Walk(stale, false)
	if _, ok, err := walker.Next(); ok || err != galley.ErrStaleTree {
		t.Fatalf("expected ErrStaleTree at the first step, ok=%v err=%v", ok, err)
	}
}

// The hook door's walk crosses galley_hook_walk_next over the in-flight
// tree and reproduces exactly what the session door walks after the parse
// publishes that tree.
func TestWalkInsideHookEqualsPostParseWalk(t *testing.T) {
	resetDoorRecording()
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("parse: %v", err)
	}
	if hookWalkErr != nil {
		t.Fatalf("hook walk step: %v", hookWalkErr)
	}
	if len(hookWalkVisits) == 0 {
		t.Fatal("the hook walk yielded nothing")
	}
	if hookWalkVisits[0].Depth != 0 {
		t.Fatalf("the hook walk's root sat at depth %d, want 0", hookWalkVisits[0].Depth)
	}
	root, ok, err := session.RootNode()
	if err != nil || !ok {
		t.Fatal("expected a root node")
	}
	walker := session.Walk(root, false)
	var post []galley.WalkStep
	for {
		step, ok, err := walker.Next()
		if err != nil {
			t.Fatalf("post-parse walk step: %v", err)
		}
		if !ok {
			break
		}
		post = append(post, step)
	}
	if len(post) != len(hookWalkVisits) {
		t.Fatalf("hook walk visited %d nodes, post-parse walk %d", len(hookWalkVisits), len(post))
	}
	for i := range post {
		if post[i] != hookWalkVisits[i] {
			t.Fatalf("step %d: post-parse %+v, hook %+v", i, post[i], hookWalkVisits[i])
		}
	}
}
