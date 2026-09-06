/**
 * Universal Galley JavaScript bindings — public surface.
 *
 * One package for Node, Bun, Deno, and browsers over `galley-js-core`,
 * with native-first backend selection and WebAssembly fallback. Call
 * `await init()` once, then use the synchronous `Session` API; under Node
 * and Bun the backend also resolves synchronously on first use.
 */

import { ensureSync } from "./loader.js";
import { Session } from "./session.js";

// Core surface (Session base is shadowed by the adapter subclass below).
export * from "galley-js-core";
export { Session };
export {
  init,
  backend,
  currentBackend,
  detectRuntime,
  type InitOptions,
  type Runtime,
  type Backend,
} from "./loader.js";
export type { UniversalSessionOptions } from "./session.js";
export type { SessionOptions, WalkStep, Diagnostic } from "galley-js-core";

// Module-level queries (mirror galley.h)
export function version(): string {
  return ensureSync().version();
}

export function parserType(): number {
  return ensureSync().parserType();
}

export function errorRecoveryMode(): number {
  return ensureSync().errorRecoveryMode();
}

export function hasAst(): boolean {
  return ensureSync().hasAst();
}

export function hasProcedures(): boolean {
  return ensureSync().hasProcedures();
}

export function allowsNoAstTreeProcedures(): boolean {
  return ensureSync().allowsNoAstTreeProcedures();
}

export function sourceRetentionEnabled(): boolean {
  return ensureSync().sourceRetentionEnabled();
}

export function hasPositionTracking(): boolean {
  return ensureSync().hasPositionTracking();
}

export function hasInputStreaming(): boolean {
  return ensureSync().hasInputStreaming();
}

export function usesVerbatim(): boolean {
  return ensureSync().usesVerbatim();
}

export function stackOverflowRecoveryAvailable(): boolean {
  return ensureSync().stackOverflowRecoveryAvailable();
}

export function symbolCount(): number {
  return ensureSync().symbolCount();
}

export function variableCount(): number {
  return ensureSync().variableCount();
}

export function statusString(status: number): string | null {
  return ensureSync().statusString(status);
}

// Preserve original Python naming aliases for docs parity
export const has_ast = hasAst;
export const has_procedures = hasProcedures;
export const has_position_tracking = hasPositionTracking;
