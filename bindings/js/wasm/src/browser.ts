/**
 * Browser entry for the WebAssembly adapter: the wasm-only surface with
 * zero `node:` specifiers anywhere in its import graph.
 *
 * Same modules as the Node entry minus the Node capabilities (`files.ts`
 * is never imported, so `findLibrary` is absent — browsers have no file
 * discovery): `await init({ url })` (or `{ bytes }`) first, then use the
 * synchronous `Session` API. Register procedure hooks explicitly with
 * `installProcedures` from `@sanbus/galley-core`.
 */

export * from "@sanbus/galley-core";
export { Session } from "./session.ts";
export {
  init,
  initSync,
  getWasmPort,
  seedDefault,
  NeedInitError,
  wasmFileName,
  version,
  parserType,
  errorRecoveryMode,
  hasAst,
  hasProcedures,
  allowsNoAstTreeProcedures,
  sourceRetentionEnabled,
  hasPositionTracking,
  hasInputStreaming,
  usesVerbatim,
  stackOverflowRecoveryAvailable,
  symbolCount,
  variableCount,
  statusString,
  has_ast,
  has_procedures,
  has_position_tracking,
} from "./ffi.ts";
export type { InitOptions } from "./ffi.ts";
export type { SessionOptions, WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";
