/**
 * Universal Galley JavaScript bindings — public surface.
 *
 * One package for Node, Bun, Deno, and browsers over `@sanbus/galley-core`,
 * with native-first backend selection and WebAssembly fallback. Call
 * `await init()` once, then use the synchronous `Session` API; under Node
 * and Bun the backend also resolves synchronously on first use.
 */

import { createRequire } from "node:module";
import { ensureSync, seedEngineLegs } from "./loader.ts";
import { Session } from "./session.ts";

// Default entry owns adapter acquisition: synchronous `require` plus
// dynamic `import`, both scoped to runtimes that have them. The browser
// entry (`browser.ts`) seeds nothing and never imports `loader.ts`.
seedEngineLegs({
  requireModule: (specifier) => createRequire(import.meta.url)(specifier) as Record<string, unknown>,
  importModule: async (specifier) => (await import(specifier)) as Record<string, unknown>,
});

// Core surface (Session base is shadowed by the adapter subclass below).
export * from "@sanbus/galley-core";
export { Session };
export {
  init,
  backend,
  currentBackend,
  detectRuntime,
  type InitOptions,
  type Runtime,
  type Backend,
} from "./loader.ts";
export type { UniversalSessionOptions } from "./session.ts";
export type { SessionOptions, WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";

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
