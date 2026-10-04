package testfixture

import (
	"bytes"
	"errors"
	"testing"

	galley "github.com/sanbus-org/galley/bindings/go/testfixture/galley"
)

// A parse that fails after running to its end publishes its tree: semantic
// errors mark nodes, recovered syntax errors leave nodes over the damaged
// input, and Parse still raises. Go reads the semantic-error flag; the
// recovered flag and the snapshot's flag columns arrive with the rest of the
// shared surface.

func publishedSession(t *testing.T, options galley.SessionOptions) *galley.Session {
	t.Helper()
	session, err := galley.WithOptions(options)
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(session.Close)
	return session
}

func TestSemanticOnlyFailurePublishesItsTree(t *testing.T) {
	session := publishedSession(t, galley.DefaultOptions())
	input := []byte("alpha:1,beta:2000")
	if _, err := session.Parse(input); !errors.Is(err, galley.ErrSemantic) {
		t.Fatalf("expected ErrSemantic, got %v", err)
	}
	root, ok, err := session.RootNode()
	if err != nil || !ok {
		t.Fatalf("root = (ok %v, %v), want the published tree", ok, err)
	}

	count := func(skip bool) (steps, marked int) {
		walker := session.Walk(root, skip)
		for {
			step, ok, err := walker.Next()
			if err != nil {
				t.Fatalf("walk step: %v", err)
			}
			if !ok {
				return
			}
			steps++
			if step.IsSemanticError {
				marked++
			}
		}
	}
	full, marked := count(false)
	if marked != 1 {
		t.Fatalf("%d semantic-error steps, want 1", marked)
	}
	pruned, prunedMarked := count(true)
	if pruned >= full || prunedMarked != 0 {
		t.Fatalf("skip walk = (%d steps, %d marked), want fewer than %d and none marked", pruned, prunedMarked, full)
	}

	if got, err := session.LastInput(); err != nil || !bytes.Equal(got, input) {
		t.Fatalf("last input = (%q, %v), want %q", got, err, input)
	}
	if info, withAST, err := session.Info(); err != nil || !withAST || !info.RootValid {
		t.Fatalf("info = (%+v, %v, %v), want a published summary", info, withAST, err)
	}

	// The next parse retires the errored tree's nodes.
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("clean parse: %v", err)
	}
	if _, err := session.Text(root); err != galley.ErrStaleTree {
		t.Fatalf("read of the errored tree's node = %v, want ErrStaleTree", err)
	}
}

func TestRecoveredSyntaxErrorPublishesItsTree(t *testing.T) {
	session := publishedSession(t, galley.DefaultOptions())
	input := []byte("alpha:x,beta:2")
	if _, err := session.Parse(input); !errors.Is(err, galley.ErrSyntax) {
		t.Fatalf("expected ErrSyntax, got %v", err)
	}
	root, ok, err := session.RootNode()
	if err != nil || !ok {
		t.Fatalf("root = (ok %v, %v), want the published tree", ok, err)
	}
	if count, err := session.NodeCount(); err != nil || count == 0 {
		t.Fatalf("node count = (%d, %v), want the published tree's", count, err)
	}
	if got, err := session.LastInput(); err != nil || !bytes.Equal(got, input) {
		t.Fatalf("last input = (%q, %v), want %q", got, err, input)
	}
	snap, err := session.Snapshot()
	if err != nil || snap.Count == 0 {
		t.Fatalf("snapshot = (count %d, %v), want the published tree's", snap.Count, err)
	}
	// The damaged Number spans the input recovery skipped: `x,beta:`.
	damaged := false
	for address := uint64(0); address < snap.Count; address++ {
		if snap.SpanStart[address] == 6 && snap.SpanLen[address] == 7 {
			damaged = true
		}
	}
	if !damaged {
		t.Fatal("expected a node spanning the skipped input")
	}

	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("clean parse: %v", err)
	}
	if _, err := session.Text(root); err != galley.ErrStaleTree {
		t.Fatalf("read of the errored tree's node = %v, want ErrStaleTree", err)
	}
}

func TestUnrecoveredSyntaxErrorPublishesNothing(t *testing.T) {
	// One error is the limit, so the parse raises instead of recovering.
	options := galley.DefaultOptions()
	options.MaxErrors = 1
	session := publishedSession(t, options)
	if _, err := session.Parse([]byte("alpha:x,beta:2")); !errors.Is(err, galley.ErrSyntax) {
		t.Fatalf("expected ErrSyntax, got %v", err)
	}
	if _, ok, err := session.RootNode(); ok || err != nil {
		t.Fatalf("root = (ok %v, %v), want (false, nil)", ok, err)
	}
	if input, err := session.LastInput(); err != galley.ErrStaleTree || input != nil {
		t.Fatalf("last input = (%q, %v), want (nil, ErrStaleTree)", input, err)
	}
	if _, _, err := session.Info(); err != galley.ErrStaleTree {
		t.Fatalf("info = %v, want ErrStaleTree", err)
	}
	if _, err := session.NodeCount(); err != galley.ErrStaleTree {
		t.Fatalf("node count = %v, want ErrStaleTree", err)
	}
}

func TestLastInputAndInfoRefuseBeforeAnyParse(t *testing.T) {
	session := publishedSession(t, galley.DefaultOptions())
	if input, err := session.LastInput(); err != galley.ErrStaleTree || input != nil {
		t.Fatalf("last input = (%q, %v), want (nil, ErrStaleTree)", input, err)
	}
	if _, _, err := session.Info(); err != galley.ErrStaleTree {
		t.Fatalf("info = %v, want ErrStaleTree", err)
	}
}
