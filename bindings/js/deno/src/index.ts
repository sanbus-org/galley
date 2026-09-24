/**
 * Galley JavaScript bindings for Deno — public surface.
 *
 * Binds the runtime-neutral `@sanbus/galley-core` to the `Deno.dlopen`
 * port, over the C header `bindings/c/galley.h`. Requires `--allow-ffi
 * --allow-read`.
 */

// Core surface: sessions come from the universal entry or the generated
// package entry; the adapter binds ports only.
export {
  Walker,
  Node,
  Parser,
  GalleyError,
  MissingArtifactError,
  SessionClosedError,
  ProcedureArguments,
  INVALID_NODE,
  Status,
  ParserType,
  RecoveryMode,
  Kind,
  RecoveryTarget,
  Resume,
} from "@sanbus/galley-core";
export { getDenoPort, getDenoPortFromFile, libFileName } from "./ffi.ts";
export { findProceduresFile, loadProcedures } from "./dispatch.ts";
export type { Session, SessionOptions, WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";
