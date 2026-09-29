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
