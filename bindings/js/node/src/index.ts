/**
 * Galley JavaScript bindings for Node — public surface.
 *
 * Binds the runtime-neutral `@sanbus/galley-core` to the addon port. Mirrors the
 * layout of `bindings/python/galley.pyi` and the C header
 * `bindings/c/galley.h`.
 */

import { Session } from "./session.ts";

// Core surface (Session base is shadowed by the adapter subclass below).
export * from "@sanbus/galley-core";
export { Session };
export { getNodePort, getNodePortFromFile, libFileName } from "./ffi.ts";
export { loadProcedures, loadProceduresForFile } from "./dispatch.ts";
export type { SessionOptions, WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";
