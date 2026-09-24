/**
 * Browser entry for the WebAssembly adapter: the wasm-only port helpers
 * with zero `node:` specifiers anywhere in the import graph. Sessions
 * come from `@sanbus/galley/browser` (`galley.loadBytes` /
 * `galley.loadUrl`).
 */

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
export { getWasmPort, instantiateWasm, portFromBytes, portFromUrl, __resetModuleCache, __resetWasmAcquisition, wasmFileName } from "./ffi.ts";
export type { WasmPortSource } from "./ffi.ts";
export type { Session, SessionOptions } from "@sanbus/galley-core";
export type { WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";
