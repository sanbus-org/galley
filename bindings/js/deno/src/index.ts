/**
 * Galley JavaScript bindings for Deno — public surface.
 *
 * Binds the runtime-neutral `@sanbus/galley-core` to the `Deno.dlopen` port.
 * Mirrors the layout of `bindings/python/galley.pyi` and the C header
 * `bindings/c/galley.h`. Requires `--allow-ffi --allow-read`.
 */

import { Session } from "./session.ts";

// Core surface (Session base is shadowed by the adapter subclass below).
export * from "@sanbus/galley-core";
export { Session };
export { getDenoPort, getDenoPortFromFile, libFileName } from "./ffi.ts";
export { findProceduresFile, loadProcedures } from "./dispatch.ts";
export type { SessionOptions, WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";
