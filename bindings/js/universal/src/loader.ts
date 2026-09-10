/**
 * Universal loader for the Galley JavaScript bindings.
 *
 * Binds the runtime-neutral `@sanbus/galley-core` to one of four backends —
 * the Node, Bun, and Deno native adapters, or the WebAssembly adapter —
 * selected per runtime with native-first ordering:
 *
 * - Node: NAPI addon → wasm → compile error.
 * - Bun: `bun:ffi` native → wasm → compile error.
 * - Deno: `Deno.dlopen` native → wasm → compile error.
 * - Browser: wasm only.
 *
 * Adapter acquisition is injected (`seedEngineLegs`): the loader names
 * backend specifiers but never imports them, so no backend — present or
 * absent — can fail this module's load. A backend missing from
 * `node_modules` degrades to "unavailable" instead of failing the load.
 * Each adapter resolves exactly one named artifact or throws
 * `MissingArtifactError`; the loader catches exactly that class to try
 * the next engine. A present-but-broken library throws anything else and
 * fails loudly instead of silently falling back.
 */

import type { FfiPort } from "@sanbus/galley-core";
import { MissingArtifactError } from "@sanbus/galley-core";

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
  getPort(explicit?: string): FfiPort;
}

interface WasmAdapter {
  init(options?: { libraryPath?: string; url?: string | URL; bytes?: Uint8Array }): Promise<void>;
  initSync(options?: { libraryPath?: string; bytes?: Uint8Array }): void;
  getWasmPort(libraryPath?: string): FfiPort;
  NeedInitError: new (...args: Array<never>) => Error;
}

const NATIVE_ADAPTERS: Record<NativeRuntime, { module: string; port: string }> = {
  node: { module: "@sanbus/galley-node", port: "getNodePort" },
  bun: { module: "@sanbus/galley-bun", port: "getBunPort" },
  deno: { module: "@sanbus/galley-deno", port: "getDenoPort" },
};
const WASM_MODULE = "@sanbus/galley-wasm";

/**
 * Adapter acquisition, injected by the entry point. The loader names
 * backend specifiers but never imports them: static or dynamic imports
 * here would pull the native adapters into every graph that loads this
 * module (bundlers follow bare specifiers because they are installed
 * dependencies), which is exactly what the browser entry must avoid.
 * The default entry (`index.ts`) seeds the Node implementations; the
 * browser entry seeds nothing and never imports this module.
 * Without seeded legs the loader resolves nothing and `init()` fails
 * with the compile guidance — there is no unseeded fallback import.
 */
export interface EngineLegs {
  /** Synchronous `require`, or absent where none exists (browsers). */
  requireModule?: (specifier: string) => Record<string, unknown>;
  /** Dynamic `import`, or absent where backends resolve another way. */
  importModule?: (specifier: string) => Promise<Record<string, unknown>>;
}

let legs: EngineLegs = {};

/** Entry points wire adapter acquisition; the loader only names backends. */
export function seedEngineLegs(seeded: EngineLegs): void {
  legs = { ...legs, ...seeded };
}

function isWasmPath(value: string | undefined): boolean {
  return !!value && value.toLowerCase().endsWith(".wasm");
}

async function loadNativeAdapter(runtime: NativeRuntime): Promise<NativeAdapter | null> {
  if (!legs.importModule) return null;
  const { module: specifier, port } = NATIVE_ADAPTERS[runtime];
  let loaded: Record<string, unknown> | null;
  try {
    loaded = await legs.importModule(specifier);
  } catch {
    return null;
  }
  if (!loaded) return null;
  const getPort = loaded[port];
  if (typeof getPort !== "function") return null;
  return { getPort: getPort as NativeAdapter["getPort"] };
}

async function loadWasmAdapter(): Promise<WasmAdapter | null> {
  if (!legs.importModule) return null;
  let loaded: Record<string, unknown> | null;
  try {
    loaded = await legs.importModule(WASM_MODULE);
  } catch {
    return null;
  }
  if (
    !loaded ||
    typeof loaded["init"] !== "function" ||
    typeof loaded["getWasmPort"] !== "function" ||
    typeof loaded["NeedInitError"] !== "function"
  ) {
    return null;
  }
  return loaded as unknown as WasmAdapter;
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
      "Build one first: npx galley build <language-dir>\n" +
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

/** Try the native leg. A missing artifact yields null; a present-but-broken
 * library throws loudly (an ABI mismatch is a user error, not a
 * fallback case). */
async function tryNative(
  runtime: NativeRuntime,
  libraryPath: string | undefined,
): Promise<FfiPort | null> {
  const adapter = await loadNativeAdapter(runtime);
  if (!adapter) return null;
  try {
    return adapter.getPort(libraryPath);
  } catch (error) {
    if (MissingArtifactError.is(error)) return null;
    throw error;
  }
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
    if (MissingArtifactError.is(error)) return null;
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
 * Synchronous resolution for Node and Bun (dynamic import is async,
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
  // Synchronous require: this branch runs under Node and Bun only, through
  // the leg the entry point seeded. Falls back to null when the package
  // is absent (or no leg was seeded).
  if (!legs.requireModule) return null;
  try {
    return legs.requireModule(specifier);
  } catch {
    return null;
  }
}

/** Synchronous native attempt (Node/Bun only). */
function tryNativeSync(runtime: NativeRuntime, libraryPath: string | undefined): FfiPort | null {
  const { module: specifier, port } = NATIVE_ADAPTERS[runtime];
  const loaded = requireAdapterModule(specifier);
  if (!loaded) return null;
  const getPort = loaded[port];
  if (typeof getPort !== "function") return null;
  try {
    return (getPort as NativeAdapter["getPort"])(libraryPath);
  } catch (error) {
    if (MissingArtifactError.is(error)) return null;
    throw error;
  }
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
    if (MissingArtifactError.is(error)) return null;
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
