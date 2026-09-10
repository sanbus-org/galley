/**
 * Galley JavaScript bindings over WebAssembly — public surface.
 *
 * Binds the runtime-neutral `@sanbus/galley-core` to the wasm port. Mirrors the
 * layout of the Node adapter and the C header `bindings/c/galley.h`.
 *
 * Initialization: `await init()` (required in browsers; optional under Node
 * where the module auto-initializes synchronously on first use).
 */

import {
  getWasmPort,
  findLibrary,
  init,
  initSync,
  seedDefault,
  NeedInitError,
  seedFileIo,
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
import { Session } from "./session.ts";
import { seedDirScanner } from "./dispatch.ts";
import { nodeFileIo, scanLanguageDir } from "./files.ts";

// Node entry owns the Node capabilities: the real filesystem plus the
// language-directory procedure auto-scan. The browser entry
// (`browser.ts`) never imports this module.
seedFileIo(nodeFileIo);
seedDirScanner(scanLanguageDir);

// Core surface (Session base is shadowed by the adapter subclass below).
export * from "@sanbus/galley-core";
export { Session };
export { findLibrary, init, initSync, seedDefault, NeedInitError };
export { getWasmPort, wasmFileName } from "./ffi.ts";
export {
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
};
export type { InitOptions } from "./ffi.ts";
export type { SessionOptions, WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";
