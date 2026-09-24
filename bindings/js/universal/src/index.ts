/**
 * Universal Galley JavaScript bindings — public surface.
 *
 * One package for Node, Bun, Deno, and browsers over `@sanbus/galley-core`,
 * with native-first backend selection and WebAssembly fallback. Parsers
 * come from the `galley` object — `load` (an explicit artifact file),
 * `loadBytes` (raw wasm), `loadUrl` (fetched) — or from a generated
 * package entry, which opens its own directory with bundled hooks.
 * Sessions open from a parser and share its hook table.
 */

import { createRequire } from "node:module";
import { seedEngineLegs } from "./loader.ts";
import type { Session } from "./session.ts";

// Default entry owns adapter acquisition: synchronous `require` plus
// dynamic `import`, both scoped to runtimes that have them. The browser
// entry (`browser.ts`) seeds nothing and never imports `loader.ts`.
seedEngineLegs({
  requireModule: (specifier) => createRequire(import.meta.url)(specifier) as Record<string, unknown>,
  importModule: async (specifier) => (await import(specifier)) as Record<string, unknown>,
});

// Core surface, minus the base Session value (a type-only Session is
// exported below; construct sessions from a parser). Parser
// is shadowed by the backend-carrying subclass in ./session.ts.
export {
  Walker,
  Node,
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
export { galley, openLanguageDirectory, Parser, __resetParserCache } from "./session.ts";
export type { Session };
export { detectRuntime, seedEngineLegs } from "./loader.ts";
export type { Runtime, Backend, SessionSource, EngineLegs } from "./loader.ts";
export type { UniversalDirectoryOptions, UniversalFileOptions, UniversalWasmOptions } from "./session.ts";
export type { SessionOptions, WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";
