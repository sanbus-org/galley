package main

import (
	"testing"

	galley "github.com/sanbus-org/galley/examples/go/demo/galley"
)

func walkSession(t *testing.T, input string) (*galley.Session, galley.Node) {
	t.Helper()
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(session.Close)
	if _, err := session.Parse([]byte(input)); err != nil {
		t.Fatalf("parse: %v", err)
	}
	root, ok := session.RootNode()
	if !ok {
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
		for _, child := range session.Children(node) {
			recurse(child, depth+1)
		}
	}
	recurse(root, 0)
	if len(expected) <= 1 {
		t.Fatalf("expected a nested tree, got %d nodes", len(expected))
	}

	walker, ok := session.Walk(root, false)
	if !ok {
		t.Fatal("expected a walker")
	}
	defer walker.Close()
	var walked []visit
	for {
		step, ok := walker.Next()
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
	walker, ok := session.Walk(root, false)
	if !ok {
		t.Fatal("expected a walker")
	}
	defer walker.Close()
	first, ok := walker.Next()
	if !ok || first.Node != root || first.Depth != 0 {
		t.Fatalf("expected the root first, got %+v", first)
	}
	walker.SkipChildren()
	if _, ok := walker.Next(); ok {
		t.Fatal("expected the walk to end after pruning the root")
	}
	if _, ok := session.Walk(galley.InvalidNode, false); ok {
		t.Fatal("expected no walker for an invalid root")
	}
}
