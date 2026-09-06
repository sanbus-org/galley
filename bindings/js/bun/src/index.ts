/**
 * Galley JavaScript bindings for Bun — public surface.
 *
 * Binds the runtime-neutral `galley-js-core` to the `bun:ffi` port. Mirrors
 * the layout of `bindings/python/galley.pyi` and the C header
 * `bindings/c/galley.h`.
 */

import { getBunPort, findLibrary } from "./ffi.js";
import { Session } from "./session.js";

// Core surface (Session base is shadowed by the adapter subclass below).
export * from "galley-js-core";
export { Session };
export { findLibrary };
export { getBunPort, libFileName } from "./ffi.js";
export type { SessionOptions, WalkStep, Diagnostic } from "galley-js-core";

// Module-level queries (mirror galley.h)
export function version(): string {
  return getBunPort().version();
}

export function parserType(): number {
  return getBunPort().parserType();
}

export function errorRecoveryMode(): number {
  return getBunPort().errorRecoveryMode();
}

export function hasAst(): boolean {
  return getBunPort().hasAst();
}

export function hasProcedures(): boolean {
  return getBunPort().hasProcedures();
}

export function allowsNoAstTreeProcedures(): boolean {
  return getBunPort().allowsNoAstTreeProcedures();
}

export function sourceRetentionEnabled(): boolean {
  return getBunPort().sourceRetentionEnabled();
}

export function hasPositionTracking(): boolean {
  return getBunPort().hasPositionTracking();
}

export function hasInputStreaming(): boolean {
  return getBunPort().hasInputStreaming();
}

export function usesVerbatim(): boolean {
  return getBunPort().usesVerbatim();
}

export function stackOverflowRecoveryAvailable(): boolean {
  return getBunPort().stackOverflowRecoveryAvailable();
}

export function symbolCount(): number {
  return getBunPort().symbolCount();
}

export function variableCount(): number {
  return getBunPort().variableCount();
}

export function statusString(status: number): string | null {
  return getBunPort().statusString(status);
}

// Preserve original Python naming aliases for docs parity
export const has_ast = hasAst;
export const has_procedures = hasProcedures;
export const has_position_tracking = hasPositionTracking;
