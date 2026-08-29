# Syntax-Error Recovery and Messages

This page covers Galley's syntax-error recovery modes and how generated parsers
render syntax-error messages. It is a companion to the [Architecture](/architecture)
overview.

## Table of Contents

- [Syntax-Error Recovery](#syntax-error-recovery)
- [Syntax-Error Messages](#syntax-error-messages)

---

## Syntax-Error Recovery

Generated LL and LR parsers are fail-fast by default: a mismatch records and prints one diagnostic, then returns `ParseError.SyntaxError`. Passing `with_error_recovery = true` to the generator enables recovery. Generated parsers expose `error_recovery_mode` as `.disabled`, `.automatic`, or `.explicit`, while retaining `is_error_recovery_enabled` for compatibility.

An enabled grammar without recovery annotations uses automatic recovery. If any LHS variable, production, or RHS variable occurrence carries an `@` annotation, the parser instead uses explicit-only recovery with no automatic fallback. An annotation records an exact terminal and whether synchronization resumes before it (preserving it) or after it (consuming it). Disabled generation keeps annotations inert and emits one warning.

An automatic-mode LL syntax mismatch transfers control to a generated cold handler. The handler prints the first diagnostic at an input position, searches ahead for the failing symbol's recovery candidates, and returns a neutral parser value. The parent then continues through its ordinary generated code, naturally exposing later grammar states as recovery points.

An automatic-mode LR mismatch uses the same bounded lookahead and position-based diagnostic suppression, with recovery candidates derived from the complete terminals accepted by the current LR state. Finding a candidate skips the invalid input and retries the state. If the state cannot resynchronize, an internal result unwinds one native LR frame and, when AST construction is enabled, its semantic value; the caller recognizes it and retries in its existing frame. This continues until the nearest viable state resumes or the initial state is exhausted. Unrecoverable end-of-input stops at the original diagnostic instead of inventing a terminal.

Explicit recovery separates mismatch detection from synchronization. Once a production is committed, the parser tries the active RHS occurrence, selected production, LHS variable, and then enclosing committed reductions. LR recovery annotations are stored separately from canonical LR items, so adding or removing them cannot change closures, states, actions, gotos, or state numbering. Explicit LR state calls carry a small linked frame containing the canonical state and incoming symbol; after a mismatch, the recovery planner combines those active frames with canonical closure metadata to resolve committed scopes without a second LR stack. For each annotated occurrence, bounded graph reachability checks whether any productive closure path can avoid it; the occurrence is active only when no surviving path can, so shared-prefix states do not activate speculative scopes. Enclosing `(frame, item)` lineages are likewise deduplicated into a finite graph, and occurrence, production, and LHS scopes become candidates only when they dominate every productive exit. Neither analysis enumerates or copies closure paths. For consecutive terminals on one target, selection is deterministic: earliest input offset, longest terminal, then annotation source order. A successful recovery attaches the winning target, terminal, and resume side to the existing diagnostic, neutral-completes the damaged variable, discards its partial semantic state, and skips its occurrence, production, and variable hooks. Message-hook invocation is deferred until the structured recovery context is finalized.

Automatic recovery does not use Zig errors for internal control flow: LL void parsers return normally, AST parsers return the invalid-node sentinel, and LR state functions return an internal recovery result when a frame must unwind. Explicit LL recovery instead propagates a private `ExplicitSyntaxRecovery` signal until a committed annotated boundary synchronizes or the public entry point converts it to `ParseError.SyntaxError`; explicit LR recovery carries the equivalent result through its state frames. A session-local target-and-position guard prevents a preserved terminal from repeatedly selecting the same explicit scope. Resynchronizing completes the current recovery and permits a later mismatch to be reported separately. Automatic LL recovery can neutral-complete a missing symbol at end-of-input, while explicit recovery requires a matching synchronization terminal.

Normal automatic-mode LL child calls retain the same `try parse_child(...)` shape. Eligible automatic recovery calls use `always_tail` on the LLVM and native AArch64 backends and fall back to ordinary calls on other backends. LR state calls inspect the returned recovery result, and each state uses its existing native frame rather than a second parser stack. Neither parser scans for synchronization terminals during normal shifts or reductions; recovery lookahead allocation happens only after a mismatch. For indentation-sensitive languages, the search distance counts parser input units, including generated indent and dedent symbols. Procedures may run on partial or later-discarded trees, so an AST from erroneous input is diagnostic data rather than a guaranteed-valid syntax tree.

Recovery-enabled parsers stop after 10 syntax errors by default. Runtime callers
configure the limit and search window through `ParseOptions.max_errors` and
`ParseOptions.recovery_window`.

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
instrumentation and its deferred cleanup fold away at compile time, and the
error handlers restore `always_tail` bail-outs, so release parsers carry no
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
