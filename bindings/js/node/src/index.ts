/**
 * Galley JavaScript bindings for Node — public surface.
 *
 * Binds the runtime-neutral `@sanbus/galley-core` to the addon port. Mirrors the
 * layout of `bindings/python/galley.pyi` and the C header
 * `bindings/c/galley.h`.
 */

import { getNodePort, findLibrary } from "./ffi.ts";
import { Session } from "./session.ts";

// Core surface (Session base is shadowed by the adapter subclass below).
export * from "@sanbus/galley-core";
export { Session };
export { findLibrary };
export { getNodePort, libFileName } from "./ffi.ts";
export type { SessionOptions, WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";

// Module-level queries (mirror galley.h)
export function version(): string {
  return getNodePort().version();
}

export function parserType(): number {
  return getNodePort().parserType();
}

export function errorRecoveryMode(): number {
  return getNodePort().errorRecoveryMode();
}

export function hasAst(): boolean {
  return getNodePort().hasAst();
}

export function hasProcedures(): boolean {
  return getNodePort().hasProcedures();
}

export function allowsNoAstTreeProcedures(): boolean {
  return getNodePort().allowsNoAstTreeProcedures();
}

export function sourceRetentionEnabled(): boolean {
  return getNodePort().sourceRetentionEnabled();
}

export function hasPositionTracking(): boolean {
  return getNodePort().hasPositionTracking();
}

export function hasInputStreaming(): boolean {
  return getNodePort().hasInputStreaming();
}

export function usesVerbatim(): boolean {
  return getNodePort().usesVerbatim();
}

export function stackOverflowRecoveryAvailable(): boolean {
  return getNodePort().stackOverflowRecoveryAvailable();
}

export function symbolCount(): number {
  return getNodePort().symbolCount();
}

export function variableCount(): number {
  return getNodePort().variableCount();
}

export function statusString(status: number): string | null {
  return getNodePort().statusString(status);
}
export const has_ast = hasAst;
export const has_procedures = hasProcedures;
export const has_position_tracking = hasPositionTracking;
