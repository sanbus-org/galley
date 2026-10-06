/**
 * Galley JavaScript bindings over WebAssembly — public surface.
 *
 * Binds the runtime-neutral `@sanbus/galley-core` to the wasm port.
 *
 * Sessions come from the universal entry (`galley.load`,
 * `galley.loadBytes`, `galley.loadUrl`) or the generated package entry
 * (`openSession`); the adapter binds ports only. The browser entry
 * (`browser.ts`) holds the wasm-only port helpers with zero `node:`
 * specifiers anywhere in its import graph.
 */

import { seedFileIo } from "./ffi.ts";
import { nodeFileIo } from "./files.ts";

// Node entry owns the Node capabilities: the real filesystem. The
// browser entry (`browser.ts`) never imports this module.
seedFileIo(nodeFileIo);

// Core surface: sessions come from the universal entry or the generated
// package entry; the adapter binds ports only.
export {
  Walker,
  Node,
  Parser,
  GalleyError,
  MissingArtifactError,
  SessionClosedError,
  StaleTreeError,
  ProcedureArguments,
  INVALID_NODE,
  Status,
  ParserType,
  RecoveryMode,
  Kind,
  RecoveryTarget,
  Resume,
} from "@sanbus/galley-core";
export { getWasmPort, instantiateWasm, __resetModuleCache, __resetWasmAcquisition, wasmFileName } from "./ffi.ts";
export type { WasmPortSource } from "./ffi.ts";
export type { Session, SessionOptions } from "@sanbus/galley-core";
export type { WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";
