package testfixture

import (
	"testing"

	galley "github.com/sanbus-org/galley/bindings/go/testfixture/galley"
)

// The tree belongs to the parse, not to the hook that handed out its door:
// the door taken in an earlier hook is the same door in a later hook of the
// same parse and still reads the tree.
func TestHookDoorServesLaterHooksOfTheSameParse(t *testing.T) {
	resetDoorRecording()
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(session.Close)
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("parse: %v", err)
	}
	if !laterHookSharesDoor {
		t.Fatal("a later hook of the same parse got a different door")
	}
	if laterHookChildCount == 0 {
		t.Fatal("the earlier hook's door read no children from a later hook")
	}
}

// The hook door checks the node's generation like the session door does: from
// a hook of the second parse, a node of the first parse is refused with
// ErrStaleTree on every read, a link and a walk step.
func TestHookDoorRefusesANodeOfAnEarlierParse(t *testing.T) {
	resetDoorRecording()
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(session.Close)
	if _, err := session.Parse([]byte("alpha:12")); err != nil {
		t.Fatalf("first parse: %v", err)
	}
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("second parse: %v", err)
	}
	if len(staleReads) == 0 {
		t.Fatal("the second parse's hook recorded no stale reads")
	}
	for i, err := range staleReads {
		if err != galley.ErrStaleTree {
			t.Errorf("hook-door read %d of an earlier parse's node answered %v, want ErrStaleTree", i, err)
		}
	}
}

// A hook door is usable only while its parse runs. A hook keeps its door and
// a walker made from it: inside the hook both work; once Parse returns, every
// call through either is refused with ErrStaleTree, and so it stays after the
// next parse.
func TestHookDoorEndsWithItsParse(t *testing.T) {
	resetDoorRecording()
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(session.Close)
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("parse: %v", err)
	}
	if keptInHookWalkErr != nil || keptInHookCountErr != nil {
		t.Fatalf("inside the hook: walker %v, door %v", keptInHookWalkErr, keptInHookCountErr)
	}
	walker, door, node := keptWalker, keptDoor, keptNode
	expectStale := func(when string) {
		t.Helper()
		if _, ok, err := walker.Next(); ok || err != galley.ErrStaleTree {
			t.Fatalf("%s: kept walker Next = ok %v, err %v; want ErrStaleTree", when, ok, err)
		}
		if _, err := door.ChildCount(node); err != galley.ErrStaleTree {
			t.Fatalf("%s: kept door ChildCount err = %v; want ErrStaleTree", when, err)
		}
		if _, _, err := door.FirstChild(node); err != galley.ErrStaleTree {
			t.Fatalf("%s: kept door FirstChild err = %v; want ErrStaleTree", when, err)
		}
		if _, err := door.Text(node); err != galley.ErrStaleTree {
			t.Fatalf("%s: kept door Text err = %v; want ErrStaleTree", when, err)
		}
	}
	expectStale("after the parse")
	if _, err := session.Parse([]byte("gamma:1")); err != nil {
		t.Fatalf("second parse: %v", err)
	}
	expectStale("after the next parse")
	session.Close()
	expectStale("after the session closed")
}

// Doors of different sessions end independently: a parse that ends on one
// session leaves a hook door of another session's running parse usable.
func TestHookDoorOfOneSessionSurvivesAnotherSessionsParse(t *testing.T) {
	resetDoorRecording()
	other, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(other.Close)
	siblingSession = other
	t.Cleanup(func() { siblingSession = nil })
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(session.Close)
	if _, err := session.Parse([]byte("alpha:12")); err != nil {
		t.Fatalf("parse: %v", err)
	}
	if siblingParseErr != nil || doorAfterSiblingErr != nil {
		t.Fatalf("another session's parse ended inside the hook: parse %v, door %v", siblingParseErr, doorAfterSiblingErr)
	}
}
