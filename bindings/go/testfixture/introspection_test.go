package testfixture

import (
	"math"
	"testing"

	galley "github.com/sanbus-org/galley/bindings/go/testfixture/galley"
)

// The grammar tables describe the fixture grammar: variables and terminals
// share the symbol table, and SymbolIsTerminal tells them apart.
func TestGrammarTablesDescribeTheFixture(t *testing.T) {
	// ll.grm's shape, confirmed by generation: ten variables, five terminals.
	if galley.SymbolCount() != 15 {
		t.Fatalf("symbol count = %d, want 15", galley.SymbolCount())
	}
	if galley.VariableCount() != 10 {
		t.Fatalf("variable count = %d, want 10", galley.VariableCount())
	}

	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })

	variables := map[string]bool{}
	for index := uint64(0); index < galley.VariableCount(); index++ {
		name, err := session.VariableNameAt(index)
		if err != nil || len(name) == 0 {
			t.Fatalf("variable %d = (%q, %v), want a name", index, name, err)
		}
		if variables[string(name)] {
			t.Fatalf("variable %q listed twice", name)
		}
		variables[string(name)] = true
	}
	if !variables["Document"] {
		t.Error("the variable table is missing Document")
	}
	if !variables["Number"] {
		t.Error("the variable table is missing Number")
	}

	terminals := 0
	for index := uint64(0); index < galley.SymbolCount(); index++ {
		name, err := session.SymbolNameAt(index)
		if err != nil || len(name) == 0 {
			t.Fatalf("symbol %d = (%q, %v), want a name", index, name, err)
		}
		terminal, err := session.SymbolIsTerminal(index)
		if err != nil {
			t.Fatalf("terminal %d: %v", index, err)
		}
		if terminal {
			terminals++
		} else if !variables[string(name)] {
			t.Errorf("non-terminal %q at %d is not in the variable table", name, index)
		}
	}
	if terminals != int(galley.SymbolCount()-galley.VariableCount()) {
		t.Fatalf("%d terminals, want %d", terminals, galley.SymbolCount()-galley.VariableCount())
	}

	// Spot checks: the first symbol is the start variable, "," is a
	// terminal, and "Number" is a variable.
	if name, err := session.SymbolNameAt(0); err != nil || string(name) != "Document" {
		t.Fatalf("symbol 0 = (%q, %v), want Document", name, err)
	}
	if terminal, err := session.SymbolIsTerminal(0); err != nil || terminal {
		t.Fatalf("Document terminal = (%v, %v), want false", terminal, err)
	}
	comma := findSymbol(t, session, ",")
	if terminal, err := session.SymbolIsTerminal(comma); err != nil || !terminal {
		t.Fatalf("comma terminal = (%v, %v), want true", terminal, err)
	}
}

func findSymbol(t *testing.T, session *galley.Session, want string) uint64 {
	t.Helper()
	for index := uint64(0); index < galley.SymbolCount(); index++ {
		name, err := session.SymbolNameAt(index)
		if err != nil {
			t.Fatalf("symbol %d: %v", index, err)
		}
		if string(name) == want {
			return index
		}
	}
	t.Fatalf("no symbol named %q", want)
	return 0
}

// An index at or past a table's count is out of range; the last valid index
// answers.
func TestTableReadsRefuseOutOfRange(t *testing.T) {
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })

	if _, err := session.SymbolNameAt(galley.SymbolCount()); err != galley.ErrOutOfRange {
		t.Errorf("SymbolNameAt(count) = %v, want ErrOutOfRange", err)
	}
	if _, err := session.SymbolIsTerminal(galley.SymbolCount()); err != galley.ErrOutOfRange {
		t.Errorf("SymbolIsTerminal(count) = %v, want ErrOutOfRange", err)
	}
	if _, err := session.VariableNameAt(galley.VariableCount()); err != galley.ErrOutOfRange {
		t.Errorf("VariableNameAt(count) = %v, want ErrOutOfRange", err)
	}
	if _, err := galley.HookName(galley.HooksCount()); err != galley.ErrOutOfRange {
		t.Errorf("HookName(count) = %v, want ErrOutOfRange", err)
	}
	if _, err := session.SymbolNameAt(galley.SymbolCount() - 1); err != nil {
		t.Errorf("SymbolNameAt(count-1) = %v, want a name", err)
	}
	if _, err := session.SymbolIsTerminal(galley.SymbolCount() - 1); err != nil {
		t.Errorf("SymbolIsTerminal(count-1) = %v, want an answer", err)
	}
	if _, err := session.VariableNameAt(galley.VariableCount() - 1); err != nil {
		t.Errorf("VariableNameAt(count-1) = %v, want a name", err)
	}
}

// The session-handle table reads refuse a destroyed session with the core's
// null argument.
func TestTableReadsRefuseAfterClose(t *testing.T) {
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	if err := session.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	if _, err := session.SymbolNameAt(0); err != galley.ErrNullArgument {
		t.Errorf("SymbolNameAt after close = %v, want ErrNullArgument", err)
	}
	if _, err := session.SymbolIsTerminal(0); err != galley.ErrNullArgument {
		t.Errorf("SymbolIsTerminal after close = %v, want ErrNullArgument", err)
	}
	if _, err := session.VariableNameAt(0); err != galley.ErrNullArgument {
		t.Errorf("VariableNameAt after close = %v, want ErrNullArgument", err)
	}
}

// A library built with Go hooks forwards its hooks through generation-time
// slots, so it reports zero host hooks: there is no name to list and every
// index is out of range. (Host-shim libraries are the ones with names.)
func TestGoHookLibrariesReportNoHookNames(t *testing.T) {
	if galley.HooksCount() != 0 {
		t.Fatalf("hook count = %d, want 0 for a Go-hooked library", galley.HooksCount())
	}
	if _, err := galley.HookName(0); err != galley.ErrOutOfRange {
		t.Fatalf("HookName(0) = %v, want ErrOutOfRange", err)
	}
}

// Option values are checked by the core, alone: every value outside its
// domain comes back as invalid argument and no session is handed out, while
// zero fields and a negative finite ratio select the runtime defaults.
func TestOptionValuesAreRejectedByTheCore(t *testing.T) {
	invalid := map[string]galley.SessionOptions{
		"negative MaxErrors":             {MaxErrors: -1},
		"negative RecoveryWindow":        {RecoveryWindow: -1},
		"negative Verbosity":             {Verbosity: -1},
		"NaN ASTPreallocationRatio":      {ASTPreallocationRatio: math.NaN()},
		"infinity ASTPreallocationRatio": {ASTPreallocationRatio: math.Inf(1)},
		"negative infinity ratio":        {ASTPreallocationRatio: math.Inf(-1)},
	}
	for name, options := range invalid {
		session, err := galley.WithOptions(options)
		if err != galley.ErrInvalidArgument {
			t.Errorf("%s: err = %v, want ErrInvalidArgument", name, err)
		}
		if session != nil {
			t.Errorf("%s: a refused create handed out a session", name)
			_ = session.Close()
		}
	}

	accepted := map[string]galley.SessionOptions{
		"zero value":       {},
		"library defaults": galley.DefaultOptions(),
		"finite ratio -1":  {ASTPreallocationRatio: -1},
		"zero MaxErrors":   {MaxErrors: 0},
	}
	for name, options := range accepted {
		session, err := galley.WithOptions(options)
		if err != nil {
			t.Errorf("%s: err = %v, want a session", name, err)
			continue
		}
		if _, err := session.Parse([]byte("alpha:12")); err != nil {
			t.Errorf("%s: parse: %v", name, err)
		}
		_ = session.Close()
	}
}
