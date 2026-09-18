/**
 * Galley JavaScript bindings for Bun — public surface.
 *
 * Binds the runtime-neutral `@sanbus/galley-core` to the `bun:ffi` port. Mirrors
 * the layout of `bindings/python/galley.pyi` and the C header
 * `bindings/c/galley.h`.
 */

import { Session } from "./session.ts";

// Core surface (Session base is shadowed by the adapter subclass below).
export * from "@sanbus/galley-core";
export { Session };
export { getBunPort, getBunPortFromFile, libFileName } from "./ffi.ts";
export { loadProcedures, loadProceduresForFile } from "./dispatch.ts";
export type { SessionOptions, WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";
