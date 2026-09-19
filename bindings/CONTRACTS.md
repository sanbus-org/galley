# Binding contracts (JavaScript + Python)

Rules every host binding follows. Where the two bindings differ on
purpose, the divergence is named instead of papered over. Grammar-level
procedure semantics live in [procedures.md](../docs/procedures.md);
this file is about loading, wiring, errors, and repo conventions.

## Two entries, disjoint by construction

- **Direct package import** (`import kv`, `import { openSession } from
  "./kv/index.mjs"`): the only path where bundled `procedures` hooks
  wire automatically.
- **Bare file load** (`galley.load(<impl>)`, `Session.fromFile`):
  artifact in, handle out. Never scans for hook files; hooks arrive
  explicitly only.
- A directory load (`Session.fromDirectory`) is the import path
  spelled by path: it scans exactly like an import.

## Hook identity and precedence

- Hook names are `reduction`, `reduction_<Variable>`, `hook_<name>`.
  Anything else is ignored (JS warns on near-miss `default`-export
  hooks; the warning names the file).
- Later installs win per hook name. Explicit installs win over
  bundled scans.
- Unregistered hooks never cross into the host: per-hook gates,
  checked on the native side, default off. No host call, no string
  decode, no exception surface for hooks nobody installed.

## Always-shim artifacts

- Every build links a dispatch shim generated from the metadata hook
  list (non-empty even when the grammar disables procedures), so a
  hook installed later fires without a rebuild.
- Without the shim, installs would record without ever firing. A
  build that silently produced that state would be a worse failure
  than any loud error here.

## Native hook sources are rejected loudly

- `procedures.c` / `procedures.cpp` next to a JS/Python grammar is a
  fatal build error naming the host file to use instead
  (`procedures.ts`, `procedures.py`). Legacy C precedence is gone;
  strictness is intentional.

## Absence errors carry a remedy

- A missing artifact raises `MissingArtifactError` (JS) /
  `galley.MissingArtifactError` (Python) naming the path and the
  exact build command. Anything else surfaces the underlying error,
  never a missing report.

## Parse-time hook semantics

- Installs and clears made mid-parse apply to later parses only.
- Nested parses restore the enclosing hook set on unwind.
- A throwing hook never aborts the parse (logged/swallowed).

## Generated files

- Every generated file carries its marker banner; builders refuse to
  overwrite a file without it (move it aside instead). Guards are
  checked before anything is written: no half-written entries.
- Generated code uses explicit errors, never `assert`, for control
  flow (`python -O` strips asserts).
- Library import writes nothing to stdout. Diagnostics go to stderr,
  and only when they say something no other channel carries.

## Examples and parity

- One grammar per package directory (`kv/`, `json/`), containers per
  language (`examples/python/`, `examples/js/`).
- Example output is byte-identical across bindings on stdout and
  stderr separately; comments may state that enforced parity but
  never link one example's files to another's.

## Deliberate divergences

- **Registry scope.** Python hooks live on the grammar module
  (shared by its sessions, matching the per-artifact native gates).
  JS hooks live on the session (composed per parse from the
  `procedures` option). Same gates underneath; different ownership
  on top.
- **Entry spelling.** Python leans on the import system (`sys.path`
  + package init); JS leans on factories plus a generated package
  entry (`Session.fromDirectory` / `openSession` / `fromFile`).
  Both advertise every entry in the build's closing message.
