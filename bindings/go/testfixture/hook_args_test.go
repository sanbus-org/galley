package testfixture

import (
	"testing"

	galley "github.com/sanbus-org/galley/bindings/go/testfixture/galley"
)

// The core refuses every call made with the arguments of a hook that has
// returned (ErrStaleHook): from a later hook of the same parse, and after the
// parse alike. Nothing of the binding tracks it.
func TestProcedureArgumentsDieWithTheirHook(t *testing.T) {
	resetDoorRecording()
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(session.Close)
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(staleHookDuring) == 0 {
		t.Fatal("the Document hook recorded no calls")
	}
	for i, err := range staleHookDuring {
		if err != galley.ErrStaleHook {
			t.Errorf("call %d with a returned hook's arguments answered %v, want ErrStaleHook", i, err)
		}
	}
	root, ok, err := session.RootNode()
	if err != nil || !ok {
		t.Fatal("expected a root node")
	}
	if _, err := firstPairArgs.Door(); err != galley.ErrStaleHook {
		t.Errorf("Door of a returned hook answered %v, want ErrStaleHook", err)
	}
	for i, err := range staleHookCalls(firstPairArgs, root) {
		if err != galley.ErrStaleHook {
			t.Errorf("call %d after the parse answered %v, want ErrStaleHook", i, err)
		}
	}
}

// Arguments kept past the session's close are refused before any freed memory
// is read: every call answers the closed error, and Door does too.
func TestProcedureArgumentsAfterTheSessionIsClosed(t *testing.T) {
	resetDoorRecording()
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("parse: %v", err)
	}
	session.Close()
	calls := staleHookCalls(firstPairArgs, galley.Node{})
	if len(calls) == 0 {
		t.Fatal("no calls were made")
	}
	for i, err := range calls {
		if err != galley.ErrNullArgument {
			t.Errorf("call %d after the session closed answered %v, want the closed error", i, err)
		}
	}
}

// What describes a finished parse is refused inside a hook with session in
// use: the node capacity answers a status, never 0.
func TestNodeCapacityIsRefusedInsideAHook(t *testing.T) {
	resetDoorRecording()
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(session.Close)
	sessionProbe = session
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("parse: %v", err)
	}
	if capacityInHook != galley.ErrSessionInUse {
		t.Fatalf("NodeCapacity inside a hook = %v, want ErrSessionInUse", capacityInHook)
	}
	if capacity, err := session.NodeCapacity(); err != nil || capacity == 0 {
		t.Fatalf("NodeCapacity after the parse = %d, %v; want a capacity", capacity, err)
	}
}

// A walker belongs to the parse of the tree it was created over: a finished
// walk raises the stale-tree error after a re-parse instead of "done".
func TestFinishedWalkerIsStaleAfterAReparse(t *testing.T) {
	session, root := walkSession(t, "alpha:12,beta:3")
	walker := session.Walk(root, false)
	for {
		_, ok, err := walker.Next()
		if err != nil {
			t.Fatalf("step: %v", err)
		}
		if !ok {
			break
		}
	}
	if _, ok, err := walker.Next(); ok || err != nil {
		t.Fatalf("a finished walk should keep ending: ok %v, err %v", ok, err)
	}
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("reparse: %v", err)
	}
	if _, _, err := walker.Next(); err != galley.ErrStaleTree {
		t.Fatalf("finished walker after a re-parse = %v, want ErrStaleTree", err)
	}
}

// An edit given nodes of two parses is refused by the core with the
// stale-tree error, whichever of the two is the live one.
func TestEditMixingTwoParsesIsRefused(t *testing.T) {
	session, oldRoot := walkSession(t, "alpha:12,beta:3")
	detached, ok, err := session.TreeCleanChildren(oldRoot)
	if err != nil || !ok {
		t.Fatalf("clean children: %v", err)
	}
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("reparse: %v", err)
	}
	freshRoot, ok, err := session.RootNode()
	if err != nil || !ok {
		t.Fatal("expected a root node")
	}
	if err := session.TreeAppendChildren(freshRoot, detached); err != galley.ErrStaleTree {
		t.Fatalf("append of an old chain = %v, want ErrStaleTree", err)
	}
	if err := session.TreeInsertBefore(freshRoot, detached); err != galley.ErrStaleTree {
		t.Fatalf("insert before = %v, want ErrStaleTree", err)
	}
	if err := session.TreeInsertAfter(freshRoot, detached); err != galley.ErrStaleTree {
		t.Fatalf("insert after = %v, want ErrStaleTree", err)
	}
	if err := session.TreeInsertChildrenAt(freshRoot, 0, detached); err != galley.ErrStaleTree {
		t.Fatalf("insert children at = %v, want ErrStaleTree", err)
	}
	if err := session.TreeAppendChildren(detached, freshRoot); err != galley.ErrStaleTree {
		t.Fatalf("append to an old parent = %v, want ErrStaleTree", err)
	}
}
