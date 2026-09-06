/**
 * Galley JavaScript bindings over WebAssembly — public surface.
 *
 * Binds the runtime-neutral `galley-js-core` to the wasm port. Mirrors the
 * layout of the Node adapter and the C header `bindings/c/galley.h`.
 *
 * Initialization: `await init()` (required in browsers; optional under Node
 * where the module auto-initializes synchronously on first use).
 */

import { getWasmPort, findLibrary, init, initSync, seedDefault, NeedInitError } from "./ffi.js";
import { Session } from "./session.js";

// Core surface (Session base is shadowed by the adapter subclass below).
export * from "galley-js-core";
export { Session };
export { findLibrary, init, initSync, seedDefault, NeedInitError };
export { getWasmPort, wasmFileName } from "./ffi.js";
export type { InitOptions } from "./ffi.js";
export type { SessionOptions, WalkStep, Diagnostic } from "galley-js-core";

// Module-level queries (mirror galley.h)
export function version(): string {
  return getWasmPort().version();
}

export function parserType(): number {
  return getWasmPort().parserType();
}

export function errorRecoveryMode(): number {
  return getWasmPort().errorRecoveryMode();
}

export function hasAst(): boolean {
  return getWasmPort().hasAst();
}

export function hasProcedures(): boolean {
  return getWasmPort().hasProcedures();
}

export function allowsNoAstTreeProcedures(): boolean {
  return getWasmPort().allowsNoAstTreeProcedures();
}

export function sourceRetentionEnabled(): boolean {
  return getWasmPort().sourceRetentionEnabled();
}

export function hasPositionTracking(): boolean {
  return getWasmPort().hasPositionTracking();
}

export function hasInputStreaming(): boolean {
  return getWasmPort().hasInputStreaming();
}

export function usesVerbatim(): boolean {
  return getWasmPort().usesVerbatim();
}

export function stackOverflowRecoveryAvailable(): boolean {
  return getWasmPort().stackOverflowRecoveryAvailable();
}

export function symbolCount(): number {
  return getWasmPort().symbolCount();
}

export function variableCount(): number {
  return getWasmPort().variableCount();
}

export function statusString(status: number): string | null {
  return getWasmPort().statusString(status);
}

// Preserve original Python naming aliases for docs parity
export const has_ast = hasAst;
export const has_procedures = hasProcedures;
export const has_position_tracking = hasPositionTracking;
