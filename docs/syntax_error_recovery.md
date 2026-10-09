# Syntax-Error Recovery and Messages

This page covers Galley's syntax-error recovery modes and how generated parsers
render syntax-error messages. It is a companion to the [Architecture](/architecture)
overview.

## Table of Contents

- [Syntax-Error Recovery](#syntax-error-recovery)
- [Recovered Trees](#recovered-trees)
- [Syntax-Error Messages](#syntax-error-messages)

---

## Syntax-Error Recovery

Generated LL and LR parsers are fail-fast by default: a mismatch records and prints one diagnostic, then returns `ParseError.SyntaxError`. When error recovery is enabled, generated parsers expose `error_recovery_mode` as `.disabled`, `.automatic`, or `.explicit`, while retaining `is_error_recovery_enabled` for compatibility.

An enabled grammar without recovery annotations uses automatic recovery. If any LHS variable, production, or RHS variable occurrence carries an `@` annotation, the parser instead uses explicit-only recovery with no automatic fallback. An annotation records an exact terminal and whether synchronization resumes before it (preserving it) or after it (consuming it). When disabled, annotations remain in the grammar model but are inert at runtime; the generated parser is still valid and selects disabled mode, and the CLI emits a warning at generation time if the grammar contains recovery annotations but recovery is disabled.

An automatic-mode LL syntax mismatch transfers control to a generated cold handler. The handler prints the first diagnostic at an input position, searches ahead for the failing symbol's recovery candidates, and returns a neutral parser value. The parent then continues through its ordinary generated code, naturally exposing later grammar states as recovery points.

An automatic-mode LR mismatch uses the same bounded lookahead and position-based diagnostic suppression, with recovery candidates derived from the complete terminals accepted by the current LR state. Finding a candidate skips the invalid input and retries the state. If the state cannot resynchronize, an internal result unwinds one native LR frame and, when AST construction is enabled, its semantic value; the caller recognizes it and retries in its existing frame. This continues until the nearest viable state resumes or the initial state is exhausted. Unrecoverable end-of-input stops at the original diagnostic instead of inventing a terminal.

Explicit recovery separates mismatch detection from synchronization. Once a production is committed, the parser tries the active RHS occurrence, selected production, LHS variable, and then enclosing committed reductions. LR recovery annotations are stored separately from canonical LR items, so adding or removing them cannot change closures, states, actions, gotos, or state numbering. Explicit LR state calls carry a small linked frame containing the canonical state and incoming symbol; after a mismatch, the recovery planner combines those active frames with canonical closure metadata to resolve committed scopes without a second LR stack. For each annotated occurrence, bounded graph reachability checks whether any productive closure path can avoid it; the occurrence is active only when no surviving path can, so shared-prefix states do not activate speculative scopes. Enclosing `(frame, item)` lineages are likewise deduplicated into a finite graph, and occurrence, production, and LHS scopes become candidates only when they dominate every productive exit. Neither analysis enumerates or copies closure paths. For consecutive terminals on one target, selection is deterministic: earliest input offset, longest terminal, then annotation source order. A successful recovery attaches the winning target, terminal, and resume side to the existing diagnostic, completes the damaged variable as a flagged node (see [Recovered Trees](#recovered-trees)), and skips its occurrence, production, and variable hooks. Message-hook invocation is deferred until the structured recovery context is finalized.

Automatic recovery does not use Zig errors for internal control flow: LL void parsers return normally, AST parsers return the damaged variable's own node (flagged as recovered), and LR state functions return an internal recovery result when a frame must unwind. Explicit LL recovery instead propagates a private `ExplicitSyntaxRecovery` signal until a committed annotated boundary synchronizes or the public entry point converts it to `ParseError.SyntaxError`; explicit LR recovery carries the equivalent result through its state frames. A session-local target-and-position guard prevents a preserved terminal from repeatedly selecting the same explicit scope. Resynchronizing completes the current recovery and permits a later mismatch to be reported separately. Automatic LL recovery can neutral-complete a missing symbol at end-of-input, while explicit recovery requires a matching synchronization terminal.

Normal automatic-mode LL child calls retain the same `try parse_child(...)` shape. Eligible automatic recovery calls return directly. LR state calls inspect the returned recovery result, and each state uses its existing native frame rather than a second parser stack. Neither parser scans for synchronization terminals during normal shifts or reductions; recovery lookahead allocation happens only after a mismatch. For indentation-sensitive languages, the search distance counts parser input units, including generated indent and dedent symbols. Procedures may run on partial or later-discarded trees, so an AST from erroneous input is diagnostic data rather than a guaranteed-valid syntax tree.

Recovery-enabled parsers stop after 10 syntax errors by default. Runtime callers
configure the limit and search window through `ParseOptions.max_errors` and
`ParseOptions.recovery_window`.

### Recovered Trees

A recovery-enabled parse that runs to its end with recorded syntax errors still
returns `ParseError.SyntaxError`, but the session publishes its tree first: the
result is readable through `session.readCurrent()` (and `parseBytesLeased`
hands back the lease with the error in `lease.failure`), and a parse that only
recorded semantic errors publishes the same way. A parse the parser could not
recover from — the error limit reached, or (in LR and explicit LL recovery) no
matching recovery point — publishes nothing, and neither does a read or
indentation failure, a stack overflow, or running out of memory. Automatic LL
recovery that finds no recovery point completes the parse neutrally at the end
of the input, so it still publishes.

Recovery keeps the damaged region in the tree instead of leaving a gap, as
nodes with `is_recovered` set. The flag appears where a node-returning variable
(or, in LR, a stand-in child) was damaged; a missing terminal that the AST
suppresses is completed neutrally and leaves no flagged node, so a tree can
carry recorded syntax errors with no `is_recovered` node. Every published tree
is link-consistent: each child links back to its parent, and sibling links
agree in both directions.

- **LL (automatic and explicit):** the variable node being built when the
  mismatch was handled is kept, flagged, and attached to its parent like a
  finished child. It keeps the children parsed before the damage, and its span
  runs from the variable's start through the input recovery skipped. The
  damaged variable's hooks do not run; its parent's do, and see the flagged
  node. A self-repeating parser keeps the chain of levels it had built, flagged
  at the outermost. A variable whose rules continue into it from their last
  position parses as one loop, and recovers as its recursive calls would: the
  recovered level is flagged and the levels around it finish normally, and an
  explicit recovery that fails at one level is retried at each enclosing level,
  outward.
- **LR, explicit:** the entry that stands in for the recovered variable carries
  a flagged node, so the reduce above links it as a child where the damage was.
  It has no children (the entries recovery unwound are discarded) and spans
  what recovery discarded and skipped.
- **LR, automatic:** LR builds no node before a rule completes, so each skip or
  popped entry becomes a flagged placeholder (without a variable) spanning the
  discarded input. Placeholders wait until the first node built over them and
  are linked into its children in source order; any left at the end belong to
  the root. A popped entry's own subtree stays unreachable.

Walking with `skip_recovered_subtrees` (`GALLEY_WALK_SKIP_RECOVERED` in the C
ABI, `skip_recovered` and its equivalents in the hosts) prunes exactly the
damaged regions, and `Node.hasRecoveredSubtree` answers the same question for
one subtree. Grammars whose own hooks walk the tree during a recovered parse
should expect flagged nodes among the children of the nodes they reduce.
A published failure may have no root: when recovery skips everything before the
grammar's first symbol, no node holds the tree and `ast_root` is `null`, though
the result is still published and its input readable.

---

## Syntax-Error Messages

LL parsers report the innermost-first sequence of variables being parsed at a
syntax error. The generated parser carries two compile-time constants:

```zig
pub const syntax_error_stack_depth = root.syntax_error_stack_depth;
pub const is_syntax_error_stack_enabled = syntax_error_stack_depth > 1;
```

The runtime resolves the depth: `-Dsyntax-error-stack-depth=N` overrides the
default, otherwise the stack defaults to 5 variables in debug builds and 1 in
release builds. A depth of 1 drops the feature entirely — the push/pop
instrumentation and its deferred cleanup fold away at compile time, so release parsers carry no
stack overhead unless the build was compiled with the option. When the stack
is enabled, each LL variable parse function pushes its variable onto a ring
(consecutive repeats of a self-recursive rule occupy one slot) and pops it on
return.

The depth is also configurable per parsing session through
`ParseOptions.syntax_error_stack_depth` (`0` inherits the generated parser's
constant). A session value never adds instrumentation that the build does not
compile in, so in a release build without the build option a session cannot
turn the stack on.

The rendered message joins the captured variables innermost-first with ` <~ `:

```
SyntaxError at 3:3:
Unexpected token "?" while parsing Symbol <~ RightHandSide <~ RightHandSideLine <~ RightHandSidesTail <~ RightHandSides.
```

ANSI rendering colorizes only the variable names; the `while parsing` prefix
and the ` <~ ` separators stay uncolored.

The full message resolution order at every error site is:

1. a message override — keyed by the innermost in-progress variable, then
   `"*"` (session `message_overrides` and the language `config.zig`
   `error_messages` table);
2. grammar hooks (`--fill-error-messages` / hand-written), exact name,
   then family, then general;
3. Galley's built-in renderer.
