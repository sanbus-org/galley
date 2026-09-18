/**
 * Universal Galley JavaScript bindings — public surface.
 *
 * One package for Node, Bun, Deno, and browsers over `@sanbus/galley-core`,
 * with native-first backend selection and WebAssembly fallback. Sessions
 * come from async factories — `Session.fromDirectory` (a language
 * directory), `Session.fromFile` (an explicit artifact file),
 * `Session.fromBytes` (raw wasm), or `Session.fromUrl` (fetched) — so
 * every JS entry shares one creation shape. Session
 * methods answer every grammar query — there are no module-level
 * queries, because there is no longer a process-wide default backend.
 */

import { createRequire } from "node:module";
import { seedEngineLegs } from "./loader.ts";
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
export { detectRuntime, seedEngineLegs } from "./loader.ts";
export type { Runtime, Backend, SessionSource, EngineLegs } from "./loader.ts";
export type { UniversalDirectoryOptions, UniversalFileOptions, UniversalWasmOptions } from "./session.ts";
export type { SessionOptions, WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";
