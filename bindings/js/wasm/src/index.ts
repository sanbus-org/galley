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

import { seedFileIo, seedProceduresScan } from "./ffi.ts";
import { nodeFileIo, scanLanguageDir } from "./files.ts";

// Node entry owns the Node capabilities: the real filesystem plus the
// language-directory procedure scan. The browser entry (`browser.ts`)
// never imports this module.
seedFileIo(nodeFileIo);
seedProceduresScan({ forDirectory: scanLanguageDir });

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
export { getWasmPort, instantiateWasm, portFromBytes, portFromUrl, __resetModuleCache, __resetWasmAcquisition, loadProcedures, wasmFileName } from "./ffi.ts";
export type { WasmPortSource } from "./ffi.ts";
export type { Session, SessionOptions } from "@sanbus/galley-core";
export type { WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";
