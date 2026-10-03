package testfixture

import (
	"testing"

	galley "github.com/sanbus-org/galley/bindings/go/testfixture/galley"
)

// twoParses returns a node of the first parse and one of the second, after
// the second parse replaced the first tree.
func twoParses(t *testing.T) (*galley.Session, galley.Node, galley.Node) {
	t.Helper()
	session, first := walkSession(t, "alpha:12")
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("second parse: %v", err)
	}
	second, ok, err := session.RootNode()
	if err != nil || !ok {
		t.Fatal("expected a root node after the second parse")
	}
	return session, first, second
}

func TestNodeOfAnEarlierParseIsRefusedOnEveryRead(t *testing.T) {
	session, first, second := twoParses(t)
	reads := map[string]error{}
	_, reads["Text"] = session.Text(first)
	_, reads["SymbolName"] = session.SymbolName(first)
	_, _, reads["Span"] = session.Span(first)
	_, _, reads["LineColumn"] = session.LineColumn(first)
	_, reads["ChildCount"] = session.ChildCount(first)
	_, _, reads["FirstChild"] = session.FirstChild(first)
	_, _, reads["Parent"] = session.Parent(first)
	_, reads["Children"] = session.Children(first)
	for name, err := range reads {
		if err != galley.ErrStaleTree {
			t.Errorf("%s of a parse-1 node = %v, want ErrStaleTree", name, err)
		}
	}
	if _, err := session.Text(second); err != nil {
		t.Fatalf("read of a live node: %v", err)
	}
}

func TestNodeOfAnEarlierParseIsRefusedOnEveryEdit(t *testing.T) {
	session, first, second := twoParses(t)
	edits := map[string]error{
		"TreeAppendChildren(first, second)":   session.TreeAppendChildren(first, second),
		"TreeAppendChildren(second, first)":   session.TreeAppendChildren(second, first),
		"TreeInsertBefore(second, first)":     session.TreeInsertBefore(second, first),
		"TreeInsertAfter(second, first)":      session.TreeInsertAfter(second, first),
		"TreeInsertChildrenAt(second, first)": session.TreeInsertChildrenAt(second, 0, first),
	}
	_, _, edits["TreeCleanChildren"] = session.TreeCleanChildren(first)
	_, _, edits["TreeRemoveSelf"] = session.TreeRemoveSelf(first)
	_, _, edits["TreeRemoveSiblings"] = session.TreeRemoveSiblings(first, 1)
	_, _, edits["TreeRemoveChildrenAt"] = session.TreeRemoveChildrenAt(first, 0, 1)
	for name, err := range edits {
		if err != galley.ErrStaleTree {
			t.Errorf("%s = %v, want ErrStaleTree", name, err)
		}
	}
	if count, err := session.ChildCount(second); err != nil || count == 0 {
		t.Fatalf("the live tree changed under refused edits: (%d, %v)", count, err)
	}
}

// RootNode keeps "nothing is published" and "the core refused" apart: the
// first is (_, false, nil), the second an error.
func TestRootNodeDistinguishesNothingPublishedFromARefusal(t *testing.T) {
	resetDoorRecording()
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(session.Close)
	if _, ok, err := session.RootNode(); ok || err != nil {
		t.Fatalf("root before any parse = (ok %v, %v), want (false, nil)", ok, err)
	}
	sessionProbe = session
	t.Cleanup(resetDoorRecording)
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("parse: %v", err)
	}
	if hookRootErr != galley.ErrSessionInUse {
		t.Fatalf("root read mid-parse = %v, want ErrSessionInUse", hookRootErr)
	}
	if _, ok, err := session.RootNode(); !ok || err != nil {
		t.Fatalf("root after the parse = (ok %v, %v), want (true, nil)", ok, err)
	}
}
