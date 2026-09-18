/**
 * Browser entry for the WebAssembly adapter: the wasm-only surface with
 * zero `node:` specifiers anywhere in its import graph.
 *
 * Sessions come from async factories: `Session.fromBytes` (raw module
 * bytes) or `Session.fromUrl` (fetched). There is no `fromDirectory`:
 * browsers have no filesystem. Register procedure hooks through the
 * session's `procedures` option.
 */

export * from "@sanbus/galley-core";
export { Session } from "./session.ts";
export { getWasmPort, instantiateWasm, portFromBytes, portFromUrl, __resetModuleCache, __resetWasmAcquisition, wasmFileName } from "./ffi.ts";
export type { WasmPortSource } from "./ffi.ts";
export type { SessionOptions } from "./session.ts";
export type { WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";
