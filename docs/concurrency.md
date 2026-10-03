# Concurrency

One session, one parse at a time. Violation is reported, never waited on.

## Scope table

Each row is a checkable claim: scope, owner, gate, error.

| Scope | Contents | Owner | Gate | Error |
|---|---|---|---|---|
| Per-parse | `Context`, syntax-error stack, token | Parsing thread | Unshared by construction | None |
| Per-session buffers | Arena (`reset(retain_capacity)`), `owned_input`, node storage | Session | Write lease exclusive, read guard shared | `SessionInUse` |
| Per-session config | `message_overrides` | Session | Set at creation; never mutated during a live parse (host obligation) | Host bug |
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
* No unprotected nested parse inside a recovery scope. While one thread runs a `stack_overflow_recovery` parse, any parse on that thread whose session did not opt into recovery fails with `NestedParseDuringStackOverflowRecovery` before touching session state (generation, node storage, owned input, and input path stay as they were). Nested parses whose sessions opted in stack scopes instead, so an inner fault is caught by the inner scope.
* No pointer outlives its guard. Node, text, and diagnostic pointers are valid only while a guard is held. The next parse may reallocate node storage between parses, never mid-parse. The generation check that keeps a handle from reading retired storage runs in every build: it is a lifetime contract memory-safe hosts depend on, not a misuse check, and it costs one integer comparison per call.
* Hook-time access runs on the parsing thread. Procedure hooks and the syntax-error reporter run on the parsing thread; they must be thread-safe if a session migrates threads over its life.
* Hook state is session state. A host shim forwards each enabled hook to the dispatch callback and handle of the session that is parsing, so sessions of one library, and sessions of different libraries, parse at the same time with no hook state shared. Changing a session's hooks while a parse runs returns `SessionInUse`. The C ABI test `bindings/c/tests/test_concurrency.c` runs two libraries with two sessions each on four threads.
* Two doors, one core. Parse-time access crosses the hook door — the `*_hook_*` entry points over the parse's door (`galley_procedure_door`), ungated because the parse already holds the lease. The door is one per parse, valid for every hook of it and dead once it ends; per-hook state stays on the arguments, which die with their hook. Hosts choose the door per call: a call inside a hook dispatch of the session's running parse, on the dispatching thread, crosses the hook door, and every other call, including a hook node used from another thread, crosses the session door and is refused. The core owns the parse generation: it advances when a parse starts, `galley_hook_generation` reports it to the parse's hooks, and `galley_root_node` reports the generation of the published tree together with its root in one crossing (`0` when nothing is published, which is never live). **The core also owns the check**: every session-door node and tree call takes the generation of the tree it addresses and returns a status, refusing anything but the published one with `StaleTree`. No host caches the published generation, so no host-side reading can disagree with the core about which tree is live, and a handle has no way to ask whether it is usable — a real read answers, by refusing. The hook twins take no generation: their door exists only while its parse runs, so a host compares there, against the door's own generation. Post-parse access crosses the session door — `galley_node_*`, `galley_tree_*`, walkers, snapshots, diagnostics — behind the guards: `SessionInUse` while a parse holds the session, `StaleTree` once a later parse, successful or failed, has retired the generation the call carries. A walk step chooses its door per step like any other node call: the hook door from the dispatching thread of the running parse — stepping inside a hook works — and the session door otherwise, refused with `SessionInUse` mid-parse and with `StaleTree` (reported as `stale tree`) once the cursor's generation is no longer the live one. A yielded step also re-verifies its position against the tree's structure version after edits: steps follow the live links, so edits between steps are visible, and a step whose position is no longer inside the walk's root (removed, or moved elsewhere) reports `invalid node`. A session stashed from a hook crosses the same guard; there is no bypass branch.

## Host obligations

* The allocator and `std.Io` passed to `Session.init` must be thread-safe and outlive every session. Sharing a non-thread-safe allocator across workers is a host bug.
* `ParseOptions.input_path` and `ParseOptions.syntax_error_reporter` are borrowed for the session lifetime, not copied. Only `message_overrides` are duplicated.
* Do not copy a live `Session` by value. A copy forks the lock while sharing storage; it is a host bug Zig cannot forbid.
* After `SessionGenerationExhausted`, recreate the session. It is permanently read-only.
* Do not mutate message overrides or destroy a session while one of its
  parses is running on any thread.
* Unload a Galley library only when no session with recovery enabled is live.
* Barrier and overlap tests must not synchronize through shared `std.testing.io`. Use `std.Thread.Mutex` / `std.Thread.Condition` / atomics with a per-worker `Io`.
