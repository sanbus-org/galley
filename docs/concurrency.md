# Concurrency

One session, one parse at a time. Violation is reported, never waited on.

## Scope table

Each row is a checkable claim: scope, owner, gate, error.

| Scope | Contents | Owner | Gate | Error |
|---|---|---|---|---|
| Per-parse | `Context`, syntax-error stack, token | Parsing thread | Unshared by construction | None |
| Per-session buffers | Arena (`reset(retain_capacity)`), `owned_input`, node storage | Session | Write lease exclusive, read guard shared | `SessionInUse` |
| Per-session config | `message_overrides` | Session | Set at creation; never mutated during a live parse (host obligation) | Host bug |
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

* One session, one writer at a time. Readers may hold a guard concurrently. No parse may start while a guard is held. Contention returns `SessionInUse`; it never blocks.
* No unprotected nested parse inside a recovery scope. While one thread runs a `stack_overflow_recovery` parse, any parse on that thread whose session did not opt into recovery fails with `NestedParseDuringStackOverflowRecovery` before touching session state (generation, node storage, owned input, and input path stay as they were). Nested parses whose sessions opted in stack scopes instead, so an inner fault is caught by the inner scope.
* No pointer outlives its guard. Node, text, and diagnostic pointers are valid only while a guard is held. The next parse may reallocate node storage between parses, never mid-parse.
* Hook-time access runs on the parsing thread. Procedure hooks and the syntax-error reporter run on the parsing thread; they must be thread-safe if a session migrates threads over its life.

## Host obligations

* The allocator and `std.Io` passed to `Session.init` must be thread-safe and outlive every session. Sharing a non-thread-safe allocator across workers is a host bug.
* `ParseOptions.input_path` and `ParseOptions.syntax_error_reporter` are borrowed for the session lifetime, not copied. Only `message_overrides` are duplicated.
* Do not copy a live `Session` by value. A copy forks the lock while sharing storage; it is a host bug Zig cannot forbid.
* After `SessionGenerationExhausted`, recreate the session. It is permanently read-only.
* Do not mutate message overrides or destroy a session while one of its
  parses is running on any thread.
* Unload a Galley library only when no session with recovery enabled is live.
* Barrier and overlap tests must not synchronize through shared `std.testing.io`. Use `std.Thread.Mutex` / `std.Thread.Condition` / atomics with a per-worker `Io`.
