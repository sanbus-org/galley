# Concurrency

One session, one parse at a time. Violation is reported, never waited on.

## Scope table

Each row is a checkable claim: scope, owner, gate, error.

| Scope | Contents | Owner | Gate | Error |
|---|---|---|---|---|
| Per-parse | `Context`, syntax-error stack, token | Parsing thread | Unshared by construction | None |
| Per-session buffers | Arena (`reset(retain_capacity)`), `owned_input`, node storage | Session | Write lease exclusive, read guard shared | `SessionInUse` |
| Per-session config | `message_overrides` | Session | Exclusive lease (`Session.setMessageOverride`, `galley_session_set_message_override`); fixed for a parse | `SessionInUse` |
| Per-session hooks | Enabled set, dispatch callback, host handle | Session | Exclusive lease (`galley_session_set_hooks`); copied onto each parse's `Context`, so fixed for that parse | `SessionInUse` |
| Per-thread | Signal scope, alternate stack, stack bounds, signal mask | Calling thread | `threadlocal` | None |
| Per-process | `SIGSEGV`/`SIGBUS` dispositions + refcount | Process | One registry per build graph; one recovery library per process (see below) | `SignalHandlerSetupFailed`, `SignalHandlerRestoreFailed`, `StackOverflowRecoveryUnsupported` |
| Per-image | Grammar tables, generated code | Image | Read-only, zero coordination | None |
| Per-image, unsafe | `var` in user `procedures.zig` | Caller | No coordination | Host bug |

A process may use stack-overflow recovery (`ParseOptions.stack_overflow_recovery`)
from exactly one generated parser library. Multiple languages built into a
single binary share one registry and are fine; enabling recovery from two
separately built Galley libraries in one process is not supported and may
leave a stale signal handler installed after all users exit, losing the
previously installed dispositions. It cannot mis-dispatch a live parse, and
cross-library detection is best-effort only.

One language assembly per Zig binary is compiler-enforced: the runtime
sources are shared files, and one file cannot belong to two modules in one
compilation, so no Zig binary can import two runtime instantiations. Two
runtime instantiations in one address space therefore means two separately
built shared libraries, which is the opt-in multi-dylib case. Multi-language
concurrency in Zig is separate processes, or separate sessions of each
language in its own binary.

## Rules

* One session, one writer at a time. Readers may hold a guard concurrently. No parse may start while a guard is held. Contention returns `SessionInUse`; it never blocks, and a reader is refused only while a writer holds the session (`src/runtime/session-lock.zig`).
* No unprotected nested parse inside a recovery scope. While one thread runs a `stack_overflow_recovery` parse, any parse on that thread whose session did not opt into recovery fails with `NestedParseDuringStackOverflowRecovery` before touching session state (generation, node storage, and owned input stay as they were). Nested parses whose sessions opted in stack scopes instead, so an inner fault is caught by the inner scope.
* No pointer outlives its guard. Node, text, and diagnostic pointers are valid only while a guard is held. The next parse may reallocate node storage between parses, never mid-parse. The generation check that keeps a handle from reading retired storage runs in every build: it is a lifetime contract memory-safe hosts depend on, not a misuse check, and it costs one integer comparison per call.
* An in-process Zig walker belongs to the parse of the tree it was created over. `TreeWalker.init` captures the generation the session stamped on its node storage when the parse began, and `walkNext` (so `TreeWalker.next` too) compares it before every step: once a later parse has begun on the session (it then does not matter whether that parse succeeds or fails; a parse refused with `SessionInUse` or `NestedParseDuringStackOverflowRecovery` never begins and leaves the walker valid), stepping the walker fails with `error.StaleTree` (`galley_error_stale_tree` through the C ABI), including a walker that had already finished. Create a new walker over the new tree. The check is one integer comparison and holds no lock, so it cannot protect a walk from a parse running on another thread: hold a read guard (`readCurrent`) for the walk, which keeps the session from parsing.
* Hook-time access runs on the parsing thread. Procedure hooks and the syntax-error reporter run on the parsing thread; they must be thread-safe if a session migrates threads over its life.
* Hook state is session state. A host shim forwards each enabled hook to the dispatch callback and handle of the session that is parsing, so sessions of one library, and sessions of different libraries, parse at the same time with no hook state shared. Changing a session's hooks or message overrides (`Session.setMessageOverride`, `galley_session_set_message_override`) while a parse runs, from another thread or from a hook, returns `SessionInUse` and changes nothing. The C ABI test `bindings/c/tests/test_concurrency.c` runs two libraries with two sessions each on four threads.
* Two doors, one core. Parse-time access crosses the hook door — the `galley_hook_*` entry points over the parse's door (`galley_procedure_door`), lock-free because the parse already holds the lease. The two doors differ only in what they are opened on (a session, or one parse's door), never in shape or rules: the hook twins take the same arguments and return the same statuses as the session calls. The door is one per parse, valid for every hook of it and dead once it ends; per-hook state is reached with the hook's session and the ticket of its call (`galley_procedure_*`), which the core refuses with `StaleHook` once that hook has returned, whatever the host still holds. A call from any thread other than the one running the parse overlaps that parse and is refused with `SessionInUse` before the ticket is looked at, so `SessionInUse` outranks `StaleHook`. An operation that takes two nodes takes each one's generation, and the core refuses nodes of two parses with `StaleTree`. Hosts choose the door per call: a call inside a hook dispatch of the session's running parse, on the dispatching thread, crosses the hook door, and every other call, including a hook node used from another thread, crosses the session door and is refused. The core owns the parse generation: it advances when a parse starts, `galley_hook_generation` reports it to the parse's hooks, and `galley_root_node` reports the generation of the published tree together with its root in one crossing (`0` when nothing is published, which is never live). **The core also owns the check**, in one place for both doors: every node and tree call takes the generation of the tree it addresses and returns a status, refusing anything but the door's live tree with `StaleTree` — the published one on the session door, the running parse's on the hook door (generation `0` is never live). No host caches or compares a generation, so no host-side reading can disagree with the core about which tree is live, and a handle has no way to ask whether it is usable — a real read answers, by refusing. The hook door has no `SessionInUse` refusal: it is unshared by construction. Post-parse access crosses the session door — `galley_node_*`, `galley_tree_*`, walkers, snapshots, diagnostics — behind the guards: `SessionInUse` while a parse holds the session, `StaleTree` once a later parse, published or not, has retired the generation the call carries. A walk step chooses its door per step like any other node call: the hook door from the dispatching thread of the running parse — stepping inside a hook works — and the session door otherwise, refused with `SessionInUse` mid-parse and with `StaleTree` (reported as `stale tree`) once the cursor's generation is no longer the live one. A yielded step also re-verifies its position against the tree's structure version after edits: steps follow the live links, so edits between steps are visible, and a step whose position is no longer inside the walk's root (removed, or moved elsewhere) reports `invalid node`. A session stashed from a hook crosses the same guard; there is no bypass branch.

## Host obligations

* The allocator and `std.Io` passed to `Session.init` must be thread-safe and outlive every session. Sharing a non-thread-safe allocator across workers is a host bug.
* The input path belongs to the parse call that passes it: it is read only during that parse, through `Context`, and no session retains it. `ParseOptions.syntax_error_reporter` is a bare function pointer, so nothing is copied — its code must stay loaded while the session lives. Only `message_overrides` are copied, because they are the only borrowed data a session keeps.
* Do not copy a live `Session` by value. A copy forks the lock while sharing storage; it is a host bug Zig cannot forbid.
* Closing a session refuses while a parse holds it, from another thread or
  from a hook: `galley_session_destroy` calls `tryDeinit` first and returns
  `galley_error_session_in_use` with nothing freed, and `Session.deinit`
  keeps its panic (Zig callers who must not crash call `Session.tryDeinit`,
  which returns `SessionInUse`). Hosts that expose `close` — Python, Java,
  JS and Go — pass that refusal through to their caller and keep the session
  open, so no layer frees state a running parse still reads.
* A raw C ABI caller owns the handle's lifetime. The refusal above covers only
  parses the core can see: a caller holding the pointer before the core
  takes its lock is invisible to the core and reaches it afterwards, so no
  call may race a destroy that succeeds. Keep one owner per handle — or a
  count checked before the pointer can go — and free nothing while a call
  that reads the handle is in flight. A language binding makes that check as
  part of its own contract, not this one: see
  [binding contracts](https://github.com/sanbus-org/galley/blob/main/bindings/CONTRACTS.md).
* Mutate message overrides only through `Session.setMessageOverride`, never by
  writing `Session.message_overrides` directly.
* Unload a Galley library only when no session with recovery enabled is live.
* Barrier and overlap tests must not synchronize through shared `std.testing.io`. Use `std.Thread.Mutex` / `std.Thread.Condition` / atomics with a per-worker `Io`.
