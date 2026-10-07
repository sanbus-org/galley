/**
 * Universal Galley JavaScript bindings — public surface.
 *
 * One package for Node, Bun, Deno, and browsers over `@sanbus/galley-core`,
 * with native-first backend selection and WebAssembly fallback. Parsers
 * come from the `galley` object — `load` (an explicit artifact file),
 * `loadBytes` (raw wasm), `loadUrl` (fetched) — or from a generated
 * package entry, which opens its own directory with bundled hooks.
 * Every factory call hands out a new parser owning its defaults;
 * sessions open from a parser and start with a copy of them.
 */

import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { seedEngineLegs } from "./loader.ts";
import type { Session } from "./session.ts";

// Default entry owns adapter acquisition, synchronously: resolve the
// specifier through the runtime's own resolution first, then require
// the resolved file. Resolution is the difference that matters —
// Node and Bun resolve through node_modules, while Deno resolves
// through the deno.json import map (the adapter is deliberately not
// a workspace member, so no node_modules layout carries it).
// The browser entry (`browser.ts`) seeds nothing and never imports
// `loader.ts`.
seedEngineLegs({
  requireModule: (specifier) =>
    createRequire(import.meta.url)(fileURLToPath(import.meta.resolve(specifier))) as Record<string,
      unknown>,
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
  StaleTreeError,
  ProcedureArguments,
  INVALID_NODE,
  Status,
  ParserType,
  RecoveryMode,
  Kind,
  RecoveryTarget,
  Resume,
} from "@sanbus/galley-core";
export { galley, openLanguageDirectory, Parser } from "./session.ts";
export type { Session };
export { detectRuntime, seedEngineLegs } from "./loader.ts";
export type { Runtime, Backend, SessionSource, EngineLegs } from "./loader.ts";
export type { UniversalDirectoryOptions, UniversalFileOptions, UniversalWasmOptions } from "./session.ts";
export type { SessionOptions, WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";
