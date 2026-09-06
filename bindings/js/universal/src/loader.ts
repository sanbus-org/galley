/**
 * Universal loader for the Galley JavaScript bindings.
 *
 * Binds the runtime-neutral `galley-js-core` to one of four backends —
 * the Node, Bun, and Deno native adapters, or the WebAssembly adapter —
 * selected per runtime with native-first ordering:
 *
 * - Node: koffi native → wasm → compile error.
 * - Bun: `bun:ffi` native → wasm → compile error.
 * - Deno: `Deno.dlopen` native → wasm → compile error.
 * - Browser: wasm only.
 *
 * Adapters are imported dynamically by specifier string (never resolved
 * statically), so bundlers only ever see the backends that are actually
 * imported, and a backend missing from `node_modules` degrades to
 * "unavailable" instead of failing the load. Each adapter owns its own
 * artifact discovery (`findLibrary`); the loader only checks existence
 * before attempting a load, so a present-but-broken library still fails
 * loudly instead of silently falling back.
 */

import * as fs from "node:fs";
import { createRequire } from "node:module";
import type { FfiPort } from "galley-js-core";

export type Runtime = "node" | "bun" | "deno" | "browser";
export type Backend = "native" | "wasm";
export type NativeRuntime = "node" | "bun" | "deno";

export interface InitOptions {
  /** Grammar artifact path. A `.wasm` suffix forces the wasm backend. */
  libraryPath?: string;
  /** Explicit wasm module path (fallback source when native is missing). */
  wasmPath?: string;
  /** Module URL for `fetch` (browsers). */
  url?: string | URL;
  /** Raw module bytes (browsers, tests). */
  wasmBytes?: Uint8Array;
  /** Suppress the one-time WebAssembly performance notice. */
  quiet?: boolean;
}

/** Detect the current JavaScript runtime. Bun and Deno are checked before
 * Node: Bun emulates `process.versions.node`. */
export function detectRuntime(): Runtime {
  const globals = globalThis as Record<string, unknown>;
  if (typeof globals.Bun !== "undefined") return "bun";
  if (typeof globals.Deno !== "undefined") return "deno";
  const processValue = globals.process as { versions?: { node?: unknown } } | undefined;
  if (typeof processValue !== "undefined" && typeof processValue.versions?.node === "string") {
    return "node";
  }
  return "browser";
}

interface NativeAdapter {
  findLibrary(explicit?: string): string;
  getPort(explicit?: string): FfiPort;
}

interface WasmAdapter {
  init(options?: { libraryPath?: string; url?: string | URL; bytes?: Uint8Array }): Promise<void>;
  initSync(options?: { libraryPath?: string; bytes?: Uint8Array }): void;
  getWasmPort(libraryPath?: string): FfiPort;
  NeedInitError: new (...args: Array<never>) => Error;
}

const NATIVE_ADAPTERS: Record<NativeRuntime, { module: string; port: string }> = {
  node: { module: "galley-js-node", port: "getNodePort" },
  bun: { module: "galley-js-bun", port: "getBunPort" },
  deno: { module: "galley-js-deno", port: "getDenoPort" },
};
const WASM_MODULE = "galley-js-wasm";

function isWasmPath(value: string | undefined): boolean {
  return !!value && value.toLowerCase().endsWith(".wasm");
}

async function loadNativeAdapter(runtime: NativeRuntime): Promise<NativeAdapter | null> {
  const { module: specifier, port } = NATIVE_ADAPTERS[runtime];
  let loaded: Record<string, unknown>;
  try {
    // Specifier is a string on purpose: bundlers must not statically
    // resolve backends that may be absent, and tsc must not require
    // their type declarations to exist yet.
    loaded = (await import(specifier)) as Record<string, unknown>;
  } catch {
    return null;
  }
  const findLibrary = loaded["findLibrary"];
  const getPort = loaded[port];
  if (typeof findLibrary !== "function" || typeof getPort !== "function") return null;
  return {
    findLibrary: findLibrary as NativeAdapter["findLibrary"],
    getPort: getPort as NativeAdapter["getPort"],
  };
}

async function loadWasmAdapter(): Promise<WasmAdapter | null> {
  try {
    const loaded = (await import(WASM_MODULE)) as Record<string, unknown>;
    if (
      typeof loaded["init"] !== "function" ||
      typeof loaded["getWasmPort"] !== "function" ||
      typeof loaded["NeedInitError"] !== "function"
    ) {
      return null;
    }
    return loaded as unknown as WasmAdapter;
  } catch {
    return null;
  }
}

/** A resolved backend: the port plus which leg of the chain served it. */
export interface ResolvedBackend {
  port: FfiPort;
  backend: Backend;
}

let ready: ResolvedBackend | null = null;
let warnedWasm = false;

function compileGuidance(): Error {
  return new Error(
    "galley: no parser artifact found (tried native library, then WebAssembly).\n" +
      "Build one first: npx galley-js-node <language-dir> or npx galley-js-wasm <language-dir>\n" +
      "or set GALLEY_LIBRARY_PATH to the built artifact.",
  );
}

function noteWasmFallback(quiet: boolean | undefined): void {
  if (quiet || warnedWasm) return;
  warnedWasm = true;
  console.warn(
    "galley: using the WebAssembly backend (no native library found); " +
      "throughput trails native codegen (roughly three quarters). " +
      "Build a native library for full speed. Silence with { quiet: true }.",
  );
}

/** Try the native leg. Missing artifacts yield null; present-but-broken
 * libraries throw loudly (an ABI mismatch is a user error, not a
 * fallback case). */
async function tryNative(
  runtime: NativeRuntime,
  libraryPath: string | undefined,
): Promise<FfiPort | null> {
  const adapter = await loadNativeAdapter(runtime);
  if (!adapter) return null;
  const resolved = adapter.findLibrary(libraryPath);
  if (!fs.existsSync(resolved)) return null;
  return adapter.getPort(libraryPath);
}

/** Try the wasm leg through the shared adapter. */
async function tryWasm(options: InitOptions): Promise<FfiPort | null> {
  const wasm = await loadWasmAdapter();
  if (!wasm) return null;
  const explicit = options.wasmPath ?? (isWasmPath(options.libraryPath) ? options.libraryPath : undefined);
  try {
    await wasm.init({ libraryPath: explicit, url: options.url, bytes: options.wasmBytes });
  } catch (error) {
    if (error instanceof wasm.NeedInitError) throw error;
    if (error instanceof Error && error.message.includes("not found")) return null;
    throw error;
  }
  return wasm.getWasmPort(explicit);
}

/**
 * Resolve and initialize the backend for `options`, caching the result.
 * Order: explicit `.wasm` path pins wasm; otherwise native first, then
 * wasm discovery, then a compile-guidance error. Browsers skip native
 * attempts (no FFI); non-Node runtimes without a prior `init()` cannot
 * synchronously initialize wasm and surface the adapter's NeedInitError.
 */
export async function init(options: InitOptions = {}): Promise<ResolvedBackend> {
  const runtime = detectRuntime();
  if (isWasmPath(options.libraryPath)) {
    const wasm = await loadWasmAdapter();
    if (!wasm) throw compileGuidance();
    await wasm.init({ libraryPath: options.libraryPath, url: options.url, bytes: options.wasmBytes });
    noteWasmFallback(options.quiet);
    ready = { port: wasm.getWasmPort(options.libraryPath), backend: "wasm" };
    return ready;
  }
  if (runtime !== "browser") {
    const native = await tryNative(runtime, options.libraryPath);
    if (native) {
      ready = { port: native, backend: "native" };
      return ready;
    }
  }
  const wasmPort = await tryWasm(options);
  if (wasmPort) {
    noteWasmFallback(options.quiet);
    ready = { port: wasmPort, backend: "wasm" };
    return ready;
  }
  throw compileGuidance();
}

/** The initialized backend, or null when `init()` has not completed. */
export function currentBackend(): ResolvedBackend | null {
  return ready;
}

/** Backend selected by the last `init()` (`"native"`, `"wasm"`, or null). */
export function backend(): Backend | null {
  return ready?.backend ?? null;
}

/**
 * Synchronous resolution for Node and Bun (dynamic `import()` is async,
 * so other runtimes must `await init()` first). Used by the `Session`
 * constructor and module-level queries.
 */
export function ensureSync(options: InitOptions = {}): FfiPort {
  if (ready && !options.libraryPath && !options.wasmPath && !options.url && !options.wasmBytes) {
    return ready.port;
  }
  const runtime = detectRuntime();
  if (runtime !== "node" && runtime !== "bun") {
    throw new Error(
      "galley: call await init() before using the bindings on this runtime; " +
        "synchronous initialization is only available under Node and Bun.",
    );
  }
  if (!isWasmPath(options.libraryPath)) {
    const native = tryNativeSync(runtime, options.libraryPath);
    if (native) {
      ready = { port: native, backend: "native" };
      return native;
    }
  }
  const wasmPort = tryWasmSync(options);
  if (wasmPort) {
    noteWasmFallback(options.quiet);
    ready = { port: wasmPort, backend: "wasm" };
    return wasmPort;
  }
  throw compileGuidance();
}

function requireAdapterModule(specifier: string): Record<string, unknown> | null {
  try {
    // Synchronous require: this branch runs under Node and Bun only.
    // Falls back to null when the package is absent.
    const require = createRequire(import.meta.url);
    return require(specifier) as Record<string, unknown>;
  } catch {
    return null;
  }
}

/** Synchronous native attempt (Node/Bun only). */
function tryNativeSync(runtime: NativeRuntime, libraryPath: string | undefined): FfiPort | null {
  const { module: specifier, port } = NATIVE_ADAPTERS[runtime];
  const loaded = requireAdapterModule(specifier);
  if (!loaded) return null;
  const findLibrary = loaded["findLibrary"];
  const getPort = loaded[port];
  if (typeof findLibrary !== "function" || typeof getPort !== "function") return null;
  const resolved = (findLibrary as NativeAdapter["findLibrary"])(libraryPath);
  if (!fs.existsSync(resolved)) return null;
  return (getPort as NativeAdapter["getPort"])(libraryPath);
}

/** Synchronous wasm attempt through the shared adapter (Node/Bun only:
 * the wasm adapter reads files and instantiates synchronously there). */
function tryWasmSync(options: InitOptions): FfiPort | null {
  const loaded = requireAdapterModule(WASM_MODULE);
  if (!loaded || typeof loaded["initSync"] !== "function") return null;
  const wasm = loaded as unknown as WasmAdapter & {
    initSync(options?: { libraryPath?: string; bytes?: Uint8Array }): void;
  };
  const explicit = options.wasmPath ?? (isWasmPath(options.libraryPath) ? options.libraryPath : undefined);
  if (options.url !== undefined && options.wasmBytes === undefined) return null;
  try {
    wasm.initSync({ libraryPath: explicit, bytes: options.wasmBytes });
  } catch (error) {
    if (error instanceof Error && error.message.includes("not found")) return null;
    throw error;
  }
  const getWasmPort = loaded["getWasmPort"];
  if (typeof getWasmPort !== "function") return null;
  return (getWasmPort as WasmAdapter["getWasmPort"])(explicit);
}

/** Test-only: clear cached resolution and the fallback notice. */
export function __resetLoader(): void {
  ready = null;
  warnedWasm = false;
}
