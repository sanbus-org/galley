/**
 * Galley JavaScript bindings for Deno — public surface.
 *
 * Binds the runtime-neutral `galley-js-core` to the `Deno.dlopen` port.
 * Mirrors the layout of `bindings/python/galley.pyi` and the C header
 * `bindings/c/galley.h`. Requires `--allow-ffi --allow-read --allow-env`.
 */

import { getDenoPort, findLibrary } from "./ffi.ts";
import { Session } from "./session.ts";

// Core surface (Session base is shadowed by the adapter subclass below).
export * from "galley-js-core";
export { Session };
export { findLibrary };
export { getDenoPort } from "./ffi.ts";
import type { SessionOptions as SessionOptionsType, WalkStep as WalkStepType, Diagnostic as DiagnosticType } from "galley-js-core";
export type { SessionOptionsType as SessionOptions, WalkStepType as WalkStep, DiagnosticType as Diagnostic };

// Module-level queries (mirror galley.h)
export function version(): string {
  return getDenoPort().version();
}

export function parserType(): number {
  return getDenoPort().parserType();
}

export function errorRecoveryMode(): number {
  return getDenoPort().errorRecoveryMode();
}

export function hasAst(): boolean {
  return getDenoPort().hasAst();
}

export function hasProcedures(): boolean {
  return getDenoPort().hasProcedures();
}

export function allowsNoAstTreeProcedures(): boolean {
  return getDenoPort().allowsNoAstTreeProcedures();
}

export function sourceRetentionEnabled(): boolean {
  return getDenoPort().sourceRetentionEnabled();
}

export function hasPositionTracking(): boolean {
  return getDenoPort().hasPositionTracking();
}

export function hasInputStreaming(): boolean {
  return getDenoPort().hasInputStreaming();
}

export function usesVerbatim(): boolean {
  return getDenoPort().usesVerbatim();
}

export function stackOverflowRecoveryAvailable(): boolean {
  return getDenoPort().stackOverflowRecoveryAvailable();
}

export function symbolCount(): number {
  return getDenoPort().symbolCount();
}

export function variableCount(): number {
  return getDenoPort().variableCount();
}

export function statusString(status: number): string | null {
  return getDenoPort().statusString(status);
}

// Preserve original Python naming aliases for docs parity
export const has_ast = hasAst;
export const has_procedures = hasProcedures;
export const has_position_tracking = hasPositionTracking;
