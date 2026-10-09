package testfixture

import (
	"errors"
	"testing"

	galley "github.com/sanbus-org/galley/bindings/go/testfixture/galley"
)

// Closing the session from inside its own parse is refused like any other
// overlapping use, and the refusal changes nothing: the parse's later hooks
// still run, the session publishes and reads its tree, parses again, and
// closes once no parse is running.
func TestCloseInsideAHookIsRefusedAndLeavesTheSession(t *testing.T) {
	resetDoorRecording()
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	closeProbe = session
	defer func() {
		closeProbe = nil
		if err := session.Close(); err != nil {
			t.Errorf("final close: %v", err)
		}
	}()

	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("parse: %v", err)
	}
	if !closeAttempted {
		t.Fatal("the hook never closed the session")
	}
	if !errors.Is(closeHookErr, galley.ErrSessionInUse) {
		t.Fatalf("close inside a hook answered %v, want ErrSessionInUse", closeHookErr)
	}
	if !laterHookAfterClose {
		t.Fatal("the parse's later hooks did not run after the refused close")
	}

	// Nothing was torn down: the published tree reads and the session parses.
	root, ok, err := session.RootNode()
	if err != nil || !ok {
		t.Fatalf("root node after the refusal: ok=%v err=%v", ok, err)
	}
	if count, err := session.NodeCount(); err != nil || count == 0 {
		t.Fatalf("node count after the refusal: count=%d err=%v", count, err)
	}
	if _, err := session.ChildCount(root); err != nil {
		t.Fatalf("child count after the refusal: %v", err)
	}
	if _, err := session.Parse([]byte("alpha:4")); err != nil {
		t.Fatalf("second parse: %v", err)
	}

	if err := session.Close(); err != nil {
		t.Fatalf("close after the parse: %v", err)
	}
	if err := session.Close(); err != nil {
		t.Fatalf("second close: %v", err)
	}
}
