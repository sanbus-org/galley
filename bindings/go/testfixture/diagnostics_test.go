package testfixture

import (
	"errors"
	"path/filepath"
	"reflect"
	"testing"

	galley "github.com/sanbus-org/galley/bindings/go/testfixture/galley"
)

// A parse leg's failure carries a snapshot of the diagnostic it stopped at,
// frozen into Go when the failure is created: a later parse on the same
// session never changes what an earlier failure reports.
func TestParseFailureCarriesAFrozenDiagnosticSnapshot(t *testing.T) {
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })

	_, err = session.Parse([]byte("alpha:x,beta:2"))
	if err == nil {
		t.Fatal("expected the parse to fail")
	}
	var failure *galley.ParseError
	if !errors.As(err, &failure) {
		t.Fatalf("parse failure = %T (%v), want *galley.ParseError", err, err)
	}
	if failure.Status != galley.ErrSyntax || !errors.Is(err, galley.ErrSyntax) {
		t.Fatalf("status = %v, want ErrSyntax (errors.Is holds)", failure.Status)
	}
	if failure.Diagnostic == nil {
		t.Fatal("expected the failure to carry a diagnostic snapshot")
	}
	snapshot := *failure.Diagnostic
	if snapshot.Kind != galley.DiagnosticKindSyntax {
		t.Fatalf("kind = %d, want syntax", snapshot.Kind)
	}
	if snapshot.Offset != 6 || snapshot.Line != 1 || snapshot.Column != 7 {
		t.Fatalf("position = offset %d, %d:%d; want offset 6 at 1:7", snapshot.Offset, snapshot.Line, snapshot.Column)
	}
	if string(snapshot.UnexpectedToken) != "x" {
		t.Fatalf("unexpected token = %q, want %q", snapshot.UnexpectedToken, "x")
	}
	if len(snapshot.ExpectedTokens) == 0 {
		t.Fatal("expected tokens are missing")
	}
	if len(snapshot.Context) == 0 || snapshot.Context[0] != "Number" {
		t.Fatalf("context = %q, want [Number]", snapshot.Context)
	}
	if snapshot.Message == "" {
		t.Fatal("expected a rendered message")
	}
	if snapshot.RecoveryTarget != galley.RecoveryTargetNone {
		t.Fatalf("recovery target = %d, want none (the fixture declares no explicit recovery points)", snapshot.RecoveryTarget)
	}
	if snapshot.SyntaxErrorCount != 1 || snapshot.SemanticErrorCount != 0 {
		t.Fatalf("counts = (%d syntax, %d semantic), want (1, 0)", snapshot.SyntaxErrorCount, snapshot.SemanticErrorCount)
	}

	// The snapshot is frozen: a clean parse replaces the session's
	// diagnostic state, not the failure's copy.
	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("clean parse: %v", err)
	}
	if !reflect.DeepEqual(*failure.Diagnostic, snapshot) {
		t.Fatalf("snapshot changed after a later parse:\n got %+v\nwant %+v", *failure.Diagnostic, snapshot)
	}
}

// A failure that recorded no diagnostic carries none: an IO failure on a
// fresh session is a status, not a snapshot of nothing.
func TestParseFileFailureWithoutADiagnosticCarriesNoSnapshot(t *testing.T) {
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })

	path := filepath.Join(t.TempDir(), "missing.json")
	_, err = session.ParseFile(path)
	if err == nil {
		t.Fatal("expected the file parse to fail")
	}
	var failure *galley.ParseError
	if !errors.As(err, &failure) {
		t.Fatalf("parse failure = %T (%v), want *galley.ParseError", err, err)
	}
	if failure.Status != galley.ErrIO {
		t.Fatalf("status = %v, want ErrIO", failure.Status)
	}
	if failure.Diagnostic != nil {
		t.Fatalf("diagnostic = %+v, want none", failure.Diagnostic)
	}
}

// A session asked to parse from inside its own hook is refused with session
// in use: the refusal is a *ParseError without a snapshot, and the running
// parse keeps its open door.
func TestReentrantParseIsRefusedAndKeepsTheRunningParse(t *testing.T) {
	resetDoorRecording()
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })
	reentrantProbe = session
	t.Cleanup(resetDoorRecording)

	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("outer parse: %v", err)
	}
	var failure *galley.ParseError
	if !errors.As(reentrantParseErr, &failure) {
		t.Fatalf("reentrant parse = %T (%v), want *galley.ParseError", reentrantParseErr, reentrantParseErr)
	}
	if failure.Status != galley.ErrSessionInUse || !errors.Is(reentrantParseErr, galley.ErrSessionInUse) {
		t.Fatalf("reentrant parse status = %v, want ErrSessionInUse", failure.Status)
	}
	if failure.Diagnostic != nil {
		t.Fatalf("a refused overlap carried a snapshot: %+v", failure.Diagnostic)
	}
	if reentrantDoorErr != nil {
		t.Fatalf("the running parse's door after the refused overlap = %v, want it still usable", reentrantDoorErr)
	}
	if _, ok, err := session.RootNode(); err != nil || !ok {
		t.Fatalf("outer parse published nothing: root ok=%v err=%v", ok, err)
	}
}

// The session's post-parse diagnostic reads are refused while a parse runs:
// the in-flight parse's own diagnostic is only reachable through its door.
func TestSessionDiagnosticReadsRefuseMidParse(t *testing.T) {
	resetDoorRecording()
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })
	sessionProbe = session
	t.Cleanup(resetDoorRecording)

	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("parse: %v", err)
	}
	if sessionDiagnosticErr != galley.ErrSessionInUse {
		t.Errorf("Diagnostic mid-parse = %v, want ErrSessionInUse", sessionDiagnosticErr)
	}
	if sessionDiagnosticsErr != galley.ErrSessionInUse {
		t.Errorf("Diagnostics mid-parse = %v, want ErrSessionInUse", sessionDiagnosticsErr)
	}
	if sessionHasDiagnosticErr != galley.ErrSessionInUse {
		t.Errorf("HasDiagnostic mid-parse = %v, want ErrSessionInUse", sessionHasDiagnosticErr)
	}
}

// Every diagnostic surface refuses a destroyed session with the core's null
// argument, never by folding the refusal into an answer.
func TestDiagnosticReadsRefuseAfterClose(t *testing.T) {
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	if _, err := session.Parse([]byte("alpha:x")); err == nil {
		t.Fatal("expected the parse to fail")
	}
	if err := session.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}

	_, _, diagnosticErr := session.Diagnostic()
	_, diagnosticsErr := session.Diagnostics()
	_, hasErr := session.HasDiagnostic()
	_, syntaxErr := session.SyntaxErrorCount()
	_, semanticErr := session.SemanticErrorCount()
	reads := map[string]error{
		"Diagnostic":         diagnosticErr,
		"Diagnostics":        diagnosticsErr,
		"HasDiagnostic":      hasErr,
		"SyntaxErrorCount":   syntaxErr,
		"SemanticErrorCount": semanticErr,
	}
	for name, err := range reads {
		if err != galley.ErrNullArgument {
			t.Errorf("%s after close = %v, want ErrNullArgument", name, err)
		}
	}
}

// HasDiagnostic follows the most recent parse's failure: false before any
// parse and after a clean one, true after a failed one, and Diagnostics
// stays nil when there is nothing to report.
func TestHasDiagnosticTracksTheLastParse(t *testing.T) {
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })

	if has, err := session.HasDiagnostic(); err != nil || has {
		t.Fatalf("before any parse = (%v, %v), want (false, nil)", has, err)
	}
	if _, err := session.Parse([]byte("alpha:x")); err == nil {
		t.Fatal("expected the parse to fail")
	}
	if has, err := session.HasDiagnostic(); err != nil || !has {
		t.Fatalf("after a failed parse = (%v, %v), want (true, nil)", has, err)
	}
	if _, err := session.Parse([]byte("alpha:12")); err != nil {
		t.Fatalf("clean parse: %v", err)
	}
	if has, err := session.HasDiagnostic(); err != nil || has {
		t.Fatalf("after a clean parse = (%v, %v), want (false, nil)", has, err)
	}
	if diagnostics, err := session.Diagnostics(); err != nil || diagnostics != nil {
		t.Fatalf("Diagnostics after a clean parse = (%v, %v), want (nil, nil)", diagnostics, err)
	}
	if _, err := session.Parse([]byte("alpha:2000")); !errors.Is(err, galley.ErrSemantic) {
		t.Fatalf("expected ErrSemantic, got %v", err)
	}
	if has, err := session.HasDiagnostic(); err != nil || !has {
		t.Fatalf("after a semantic failure = (%v, %v), want (true, nil)", has, err)
	}
}

// The counts mirror the most recent parse: every recorded syntax error of a
// recovery-enabled parse, and every semantic error, each reset by the next
// parse.
func TestSyntaxAndSemanticErrorCounts(t *testing.T) {
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })

	expect := func(label string, syntax, semantic uint64) {
		t.Helper()
		gotSyntax, err := session.SyntaxErrorCount()
		if err != nil || gotSyntax != syntax {
			t.Fatalf("%s: syntax count = (%d, %v), want %d", label, gotSyntax, err, syntax)
		}
		gotSemantic, err := session.SemanticErrorCount()
		if err != nil || gotSemantic != semantic {
			t.Fatalf("%s: semantic count = (%d, %v), want %d", label, gotSemantic, err, semantic)
		}
	}

	expect("before any parse", 0, 0)
	if _, err := session.Parse([]byte("alpha:x,beta:y,gamma:z")); !errors.Is(err, galley.ErrSyntax) {
		t.Fatalf("expected ErrSyntax, got %v", err)
	}
	expect("recovered syntax errors", 3, 0)
	// Every recorded diagnostic of the parse carries the same totals.
	recorded, err := session.Diagnostics()
	if err != nil || len(recorded) != 3 {
		t.Fatalf("recorded diagnostics = (%d, %v), want 3", len(recorded), err)
	}
	for index, diagnostic := range recorded {
		if diagnostic.SyntaxErrorCount != 3 || diagnostic.SemanticErrorCount != 0 {
			t.Fatalf("recorded diagnostic %d counts = (%d, %d), want (3, 0)", index, diagnostic.SyntaxErrorCount, diagnostic.SemanticErrorCount)
		}
	}
	if _, err := session.Parse([]byte("alpha:1,beta:2000,gamma:3000")); !errors.Is(err, galley.ErrSemantic) {
		t.Fatalf("expected ErrSemantic, got %v", err)
	}
	expect("semantic errors", 0, 2)
	recorded, err = session.Diagnostics()
	if err != nil || len(recorded) != 2 {
		t.Fatalf("recorded diagnostics = (%d, %v), want 2", len(recorded), err)
	}
	for index, diagnostic := range recorded {
		if diagnostic.SyntaxErrorCount != 0 || diagnostic.SemanticErrorCount != 2 {
			t.Fatalf("recorded diagnostic %d counts = (%d, %d), want (0, 2)", index, diagnostic.SyntaxErrorCount, diagnostic.SemanticErrorCount)
		}
	}
	current, ok, err := session.Diagnostic()
	if err != nil || !ok {
		t.Fatalf("current diagnostic = (ok %v, %v)", ok, err)
	}
	if current.SyntaxErrorCount != 0 || current.SemanticErrorCount != 2 {
		t.Fatalf("current counts = (%d, %d), want (0, 2)", current.SyntaxErrorCount, current.SemanticErrorCount)
	}
	if _, err := session.Parse([]byte("alpha:12")); err != nil {
		t.Fatalf("clean parse: %v", err)
	}
	expect("after a clean parse", 0, 0)
}

// The fixture's grammar declares no explicit recovery points, so an
// automatically recovered syntax error carries no recovery target, and a
// diagnostic that is not syntax answers none too: the read is an answer,
// never a refusal.
func TestRecordedDiagnosticsCarryNoRecoveryTarget(t *testing.T) {
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })

	if _, err := session.Parse([]byte("alpha:x,beta:y,gamma:z")); !errors.Is(err, galley.ErrSyntax) {
		t.Fatalf("expected ErrSyntax, got %v", err)
	}
	diagnostics, err := session.Diagnostics()
	if err != nil {
		t.Fatalf("diagnostics: %v", err)
	}
	if len(diagnostics) != 3 {
		t.Fatalf("diagnostics = %d, want 3", len(diagnostics))
	}
	for index, diagnostic := range diagnostics {
		if diagnostic.RecoveryTarget != galley.RecoveryTargetNone {
			t.Errorf("recorded diagnostic %d recovery target = %d, want none", index, diagnostic.RecoveryTarget)
		}
	}
	current, ok, err := session.Diagnostic()
	if err != nil || !ok {
		t.Fatalf("current diagnostic = (ok %v, %v)", ok, err)
	}
	if current.RecoveryTarget != galley.RecoveryTargetNone {
		t.Fatalf("current recovery target = %d, want none", current.RecoveryTarget)
	}

	if _, err := session.Parse([]byte("alpha:2000")); !errors.Is(err, galley.ErrSemantic) {
		t.Fatalf("expected ErrSemantic, got %v", err)
	}
	semantic, ok, err := session.Diagnostic()
	if err != nil || !ok {
		t.Fatalf("semantic diagnostic = (ok %v, %v)", ok, err)
	}
	if semantic.Kind != galley.DiagnosticKindSemantic || semantic.RecoveryTarget != galley.RecoveryTargetNone {
		t.Fatalf("semantic diagnostic kind %d recovery %d, want semantic/none", semantic.Kind, semantic.RecoveryTarget)
	}
}

// The in-flight parse's diagnostic is readable through its own door: absent
// during a clean parse, the recorded semantic error during a failing one.
func TestHookDoorReadsTheRunningParsesDiagnostic(t *testing.T) {
	resetDoorRecording()
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })
	hookDiagnosticProbe = true
	t.Cleanup(resetDoorRecording)

	if _, err := session.Parse([]byte("alpha:12,beta:3")); err != nil {
		t.Fatalf("clean parse: %v", err)
	}
	if hookHasDiagnosticErr != nil || hookHasDiagnostic {
		t.Fatalf("clean parse: hook HasDiagnostic = (%v, %v), want (false, nil)", hookHasDiagnostic, hookHasDiagnosticErr)
	}
	if hookDiagnosticErr != nil || hookDiagnosticOK {
		t.Fatalf("clean parse: hook Diagnostic = (ok %v, %v), want (false, nil)", hookDiagnosticOK, hookDiagnosticErr)
	}

	if _, err := session.Parse([]byte("alpha:2000")); !errors.Is(err, galley.ErrSemantic) {
		t.Fatalf("expected ErrSemantic, got %v", err)
	}
	if hookHasDiagnosticErr != nil || !hookHasDiagnostic {
		t.Fatalf("semantic failure: hook HasDiagnostic = (%v, %v), want (true, nil)", hookHasDiagnostic, hookHasDiagnosticErr)
	}
	if hookDiagnosticErr != nil || !hookDiagnosticOK {
		t.Fatalf("semantic failure: hook Diagnostic = (ok %v, %v)", hookDiagnosticOK, hookDiagnosticErr)
	}
	if hookDiagnostic.Kind != galley.DiagnosticKindSemantic {
		t.Fatalf("hook diagnostic kind = %d, want semantic", hookDiagnostic.Kind)
	}
	if hookDiagnostic.Semantic == nil || hookDiagnostic.Semantic.Variable != "Number" {
		t.Fatalf("hook diagnostic semantic fields = %+v, want variable Number", hookDiagnostic.Semantic)
	}
	if hookDiagnostic.SyntaxErrorCount != 0 || hookDiagnostic.SemanticErrorCount != 1 {
		t.Fatalf("hook counts = (%d, %d), want (0, 1)", hookDiagnostic.SyntaxErrorCount, hookDiagnostic.SemanticErrorCount)
	}
	// The session's own doors report the same totals once the parse ended:
	// the hook snapshot and the recorded snapshot are one parse's counts,
	// each read through its own door.
	recorded, err := session.Diagnostics()
	if err != nil || len(recorded) != 1 {
		t.Fatalf("recorded diagnostics = (%d, %v), want 1", len(recorded), err)
	}
	if recorded[0].SyntaxErrorCount != 0 || recorded[0].SemanticErrorCount != 1 {
		t.Fatalf("recorded counts = (%d, %d), want (0, 1)", recorded[0].SyntaxErrorCount, recorded[0].SemanticErrorCount)
	}
}

// Recovered syntax errors are readable through the hook door too, with the
// syntax-gated fields answered by the door's twins.
func TestHookDoorReadsARecoveredSyntaxDiagnostic(t *testing.T) {
	resetDoorRecording()
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })
	hookDiagnosticProbe = true
	t.Cleanup(resetDoorRecording)

	if _, err := session.Parse([]byte("alpha:x,beta:2")); !errors.Is(err, galley.ErrSyntax) {
		t.Fatalf("expected ErrSyntax, got %v", err)
	}
	if hookHasDiagnosticErr != nil || !hookHasDiagnostic {
		t.Fatalf("hook HasDiagnostic = (%v, %v), want (true, nil)", hookHasDiagnostic, hookHasDiagnosticErr)
	}
	if hookDiagnosticErr != nil || !hookDiagnosticOK {
		t.Fatalf("hook Diagnostic = (ok %v, %v)", hookDiagnosticOK, hookDiagnosticErr)
	}
	if hookDiagnostic.Kind != galley.DiagnosticKindSyntax {
		t.Fatalf("hook diagnostic kind = %d, want syntax", hookDiagnostic.Kind)
	}
	if string(hookDiagnostic.UnexpectedToken) != "x" {
		t.Fatalf("hook unexpected token = %q, want %q", hookDiagnostic.UnexpectedToken, "x")
	}
	if len(hookDiagnostic.ExpectedTokens) == 0 || len(hookDiagnostic.Context) == 0 {
		t.Fatalf("hook syntax fields missing: expected %q, context %q", hookDiagnostic.ExpectedTokens, hookDiagnostic.Context)
	}
	if hookDiagnostic.SyntaxErrorCount != 1 || hookDiagnostic.SemanticErrorCount != 0 {
		t.Fatalf("hook counts = (%d, %d), want (1, 0)", hookDiagnostic.SyntaxErrorCount, hookDiagnostic.SemanticErrorCount)
	}
	recorded, err := session.Diagnostics()
	if err != nil || len(recorded) != 1 {
		t.Fatalf("recorded diagnostics = (%d, %v), want 1", len(recorded), err)
	}
	if recorded[0].SyntaxErrorCount != 1 || recorded[0].SemanticErrorCount != 0 {
		t.Fatalf("recorded counts = (%d, %d), want (1, 0)", recorded[0].SyntaxErrorCount, recorded[0].SemanticErrorCount)
	}
}
