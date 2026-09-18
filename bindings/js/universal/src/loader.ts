/**
 * Universal loader for the Galley JavaScript bindings.
 *
 * Binds the runtime-neutral `@sanbus/galley-core` to one of four backends —
 * the Node, Bun, and Deno native adapters, or the WebAssembly adapter —
 * selected per runtime with native-first ordering:
 *
 * - Node: NAPI addon → wasm.
 * - Bun: `bun:ffi` native → wasm.
 * - Deno: `Deno.dlopen` native → wasm.
 * - Browser: wasm only.
 *
 * There is no `init()`: the universal `Session` factories resolve their
 * backend before returning — `fromDirectory` (a directory holding the
 * standard-named artifact), `fromFile` (an explicit artifact file, with
 * the file's own directory scanned for `procedures`), `fromBytes` (raw
 * wasm), or `fromUrl` (fetched). A factory either resolves a usable
 * session or rejects: there is no unready state.
 *
 * Adapter acquisition is injected (`seedEngineLegs`): the loader names
 * backend specifiers but never imports them, so no backend — present or
 * absent — can fail this module's load. A backend missing from
 * `node_modules` degrades to "unavailable" instead of failing the load.
 * Each adapter resolves its standard-named artifact from the directory
 * or throws `MissingArtifactError`; the loader catches exactly that
 * class to try the next engine. A present-but-broken library throws
 * anything else and fails loudly instead of silently falling back.
 */

import type { FfiPort } from "@sanbus/galley-core";
import {
  MissingArtifactError,
  fetchModuleBytes,
  noteSkippedScan,
  __resetSkippedScan,
} from "@sanbus/galley-core";

// Re-exported so sessions keep one import: the loader owns backend
// resolution, and the skipped-scan notice rides with it. The once-flag
// itself lives in core, shared with the Deno adapter.
export { noteSkippedScan };

export type Runtime = "node" | "bun" | "deno" | "browser";
export type Backend = "native" | "wasm";
export type NativeRuntime = "node" | "bun" | "deno";

/** One resolved source naming the parser artifact, plus probe options. Factories pass exactly one source. */
export interface SessionSource {
  /** Language directory holding the standard-named artifact file. */
  languagePath?: string;
  /** Explicit artifact file. The file's own directory is scanned for `procedures`. */
  filePath?: string;
  /** Module URL for `fetch`. */
  url?: string | URL;
  /** Raw wasm module bytes. */
  bytes?: Uint8Array;
  /** Pin one backend instead of the native-first probe. */
  backend?: Backend;
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

interface WasmAdapter {
  getWasmPort(source: { languagePath?: string; filePath?: string; bytes?: Uint8Array }): FfiPort;
  instantiateWasm(bytes: Uint8Array): FfiPort;
  portFromBytes?(bytes: Uint8Array): Promise<FfiPort>;
  loadProcedures?(languagePath: string): Record<string, unknown> | null;
  loadProceduresForFile?(filePath: string): Record<string, unknown> | null;
}

const NATIVE_ADAPTERS: Record<NativeRuntime, { module: string; getPort: string; getPortFromFile: string }> = {
  node: { module: "@sanbus/galley-node", getPort: "getNodePort", getPortFromFile: "getNodePortFromFile" },
  bun: { module: "@sanbus/galley-bun", getPort: "getBunPort", getPortFromFile: "getBunPortFromFile" },
  deno: { module: "@sanbus/galley-deno", getPort: "getDenoPort", getPortFromFile: "getDenoPortFromFile" },
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
 * Without seeded legs the loader resolves nothing and construction
 * fails with the compile guidance — there is no unseeded fallback import.
 */
export interface EngineLegs {
  /** Synchronous `require`, or absent where none exists (browsers). */
  requireModule?: (specifier: string) => Record<string, unknown>;
  /** Dynamic `import`, or absent where backends resolve another way. */
  importModule?: (specifier: string) => Promise<Record<string, unknown>>;
}

let legs: EngineLegs = {};
let legsUsed = false;

/** Entry points wire adapter acquisition; the loader only names backends. Reseeding after the first resolution is a loud error: silent last-writer-wins would reroute backends mid-process. */
export function seedEngineLegs(seeded: EngineLegs): void {
  if (legsUsed) {
    throw new Error("galley: engine legs are already in use and cannot be reseeded");
  }
  legs = { ...legs, ...seeded };
}

/** A resolved backend: the port, which leg served it, scanned hooks, and
 * a procedures file that was detected but not loaded (runtimes without
 * a synchronous loader — the session warns about it). */
export interface ResolvedBackend {
  port: FfiPort;
  backend: Backend;
  procedures: Record<string, unknown> | null;
  unscannedProcedures: string | null;
}

let warnedWasm = false;

function compileGuidance(directory: string | undefined): Error {
  return new Error(
    "galley: no parser artifact found (tried native library, then WebAssembly).\n" +
      `Build one first: npx galley build ${directory ?? "<language-dir>"}`,
  );
}

export function noteWasmFallback(quiet: boolean | undefined): void {
  if (quiet || warnedWasm) return;
  warnedWasm = true;
  console.warn(
    "galley: using the WebAssembly backend (no native library found); " +
      "throughput trails native codegen (roughly three quarters). " +
      "Build a native library for full speed. Silence with { quiet: true }.",
  );
}

/** The single source check: exactly one of the four artifact sources.
 * Empty strings count as absent; factories report the precise error for
 * bad values, so this only guards the seam. Factories pass one source
 * by construction. */
export function checkSource(source: SessionSource): void {
  const present = (value: unknown): boolean => value !== undefined && value !== "";
  const count = [source.languagePath, source.filePath, source.url, source.bytes].filter(present).length;
  if (count !== 1) {
    throw new TypeError("galley: Session needs exactly one of languagePath, filePath, url, bytes");
  }
}

function requireAdapterModule(specifier: string): Record<string, unknown> | null {
  // Synchronous require through the leg the entry point seeded. A throwing
  // leg means the backend is unavailable here (absent package, bundler
  // stub, or an unreachable-require proof like the browser suite's), never
  // a hard failure: presence problems surface as MissingArtifactError from
  // the adapters themselves, which the probes below catch per engine.
  // Only a returned module counts as consumed for the reseed guard below.
  if (!legs.requireModule) return null;
  try {
    const loaded = legs.requireModule(specifier);
    legsUsed = true;
    return loaded;
  } catch {
    return null;
  }
}

/**
 * Whether synchronous resolution can serve this runtime: it needs a
 * require leg that honors the runtime's module mapping. Deno's require
 * resolves bare specifiers through package exports (compiled `dist`),
 * bypassing the TS sources the import map names, so Deno always takes
 * the asynchronous leg — as does any runtime without a seeded leg.
 */
function canResolveSync(runtime: Runtime): boolean {
  return runtime !== "deno" && legs.requireModule !== undefined;
}

/**
 * The single native-leg attempt behind both the sync and async probes:
 * resolves the port for a directory or file source, then the sibling
 * scan. Missing artifacts yield null (try the next engine); a
 * present-but-broken library throws loudly. `names` is the runtime's
 * row of the adapter table, so backend export names live in exactly
 * one place.
 */
function useNativeModule(
  loaded: Record<string, unknown>,
  names: { getPort: string; getPortFromFile: string },
  source: SessionSource,
): ResolvedBackend | null {
  const fromFile = source.filePath !== undefined;
  const getPortFn = loaded[fromFile ? names.getPortFromFile : names.getPort];
  if (typeof getPortFn !== "function") return null;
  const artifact = (fromFile ? source.filePath : source.languagePath) as string;
  try {
    const port = (getPortFn as (artifact: string) => FfiPort)(artifact);
    const loadProcedures = loaded[fromFile ? "loadProceduresForFile" : "loadProcedures"];
    const procedures =
      typeof loadProcedures === "function"
        ? (loadProcedures as (artifact: string) => Record<string, unknown> | null)(artifact)
        : null;
    // Detection without loading (Deno): a present-but-unscanned file is
    // reported for the session to warn about. Legs that load (or throw
    // on failure) never produce one.
    const findScan = loaded[fromFile ? "findProceduresFileForFile" : "findProceduresFile"];
    const unscannedProcedures =
      typeof findScan === "function" && procedures === null
        ? (findScan as (artifact: string) => string | null)(artifact)
        : null;
    return { port, backend: "native", procedures, unscannedProcedures };
  } catch (error) {
    if (MissingArtifactError.is(error)) return null;
    throw error;
  }
}

/** Sync probe: acquire through require, attempt through the shared body. */
function tryNativeSync(runtime: NativeRuntime, source: SessionSource): ResolvedBackend | null {
  const loaded = requireAdapterModule(NATIVE_ADAPTERS[runtime].module);
  if (!loaded) return null;
  return useNativeModule(loaded, NATIVE_ADAPTERS[runtime], source);
}

/**
 * The single file-backed wasm attempt behind both probes. Byte-fed and
 * fetched sources never reach here; callers handle those first.
 * Missing artifacts yield null, anything else throws loudly.
 */
function resolveWasmFile(wasm: WasmAdapter, source: SessionSource): ResolvedBackend | null {
  try {
    if (source.filePath !== undefined) {
      // The wasm leg serves wasm modules: anything else is another
      // engine's artifact, not a miss to compile. Yield so probing (and
      // its loud guidance) keeps working; getWasmPort itself throws for
      // direct callers.
      if (!source.filePath.toLowerCase().endsWith(".wasm")) return null;
      return {
        port: wasm.getWasmPort({ filePath: source.filePath }),
        backend: "wasm",
        procedures: wasm.loadProceduresForFile?.(source.filePath) ?? null,
        unscannedProcedures: null,
      };
    }
    if (source.languagePath === undefined) return null;
    return {
      port: wasm.getWasmPort({ languagePath: source.languagePath }),
      backend: "wasm",
      procedures: wasm.loadProcedures?.(source.languagePath) ?? null,
      unscannedProcedures: null,
    };
  } catch (error) {
    if (MissingArtifactError.is(error)) return null;
    throw error;
  }
}

/** Sync probe: acquire through require; bytes instantiate directly. */
function tryWasmSync(source: SessionSource): ResolvedBackend | null {
  const loaded = requireAdapterModule(WASM_MODULE);
  if (!loaded) return null;
  if (
    typeof loaded["getWasmPort"] !== "function" ||
    typeof loaded["instantiateWasm"] !== "function"
  ) {
    return null;
  }
  const wasm = loaded as unknown as WasmAdapter;
  if (source.bytes) {
    return { port: wasm.instantiateWasm(source.bytes), backend: "wasm", procedures: null, unscannedProcedures: null };
  }
  return resolveWasmFile(wasm, source);
}

function probeOrder(runtime: Runtime, backend: Backend | undefined): Backend[] {
  if (backend !== undefined) return [backend];
  if (runtime === "browser") return ["wasm"];
  return ["native", "wasm"];
}

/**
 * Synchronous resolution for sources that allow it. Returns the
 * resolution, or null where only an asynchronous leg can serve the
 * source (fetched `url`, or runtimes failing {@link canResolveSync}).
 * Throws when no leg can serve the source at all.
 */export function resolveSync(source: SessionSource, runtime: Runtime): ResolvedBackend | null {
  checkSource(source);
  if (source.url !== undefined) return null;
  if (!canResolveSync(runtime)) return null;
  if (source.bytes !== undefined) {
    // Byte-fed modules instantiate synchronously wherever the wasm
    // adapter loads. Errors (invalid bytes) propagate; they are user
    // errors, not fallback cases.
    return tryWasmSync(source);
  }
  const fromFile = source.filePath !== undefined;
  const display = (fromFile ? source.filePath : source.languagePath) as string;
  if (runtime === "browser") {
    throw new Error(
      fromFile
        ? "galley: browsers cannot read artifact files; pass url or bytes instead"
        : "galley: browsers cannot read language directories; pass url or bytes instead",
    );
  }
  if (runtime !== "node" && runtime !== "bun" && runtime !== "deno") {
    throw compileGuidance(display);
  }
  for (const leg of probeOrder(runtime, source.backend)) {
    const resolved =
      leg === "native" ? tryNativeSync(runtime, source) : tryWasmSync(source);
    if (resolved) return resolved;
  }
  throw compileGuidance(display);
}

async function loadAdapterModule(specifier: string): Promise<Record<string, unknown> | null> {
  // Same rule as the sync leg above: a throwing leg means unavailable.
  // Only a returned module counts as consumed for the reseed guard.
  if (!legs.importModule) return null;
  try {
    const loaded = await legs.importModule(specifier);
    legsUsed = true;
    return loaded;
  } catch {
    return null;
  }
}

/** Async probe: acquire through dynamic import, attempt through the shared body. */
async function tryNativeAsync(
  runtime: NativeRuntime,
  source: SessionSource,
): Promise<ResolvedBackend | null> {
  const loaded = await loadAdapterModule(NATIVE_ADAPTERS[runtime].module);
  if (!loaded) return null;
  return useNativeModule(loaded, NATIVE_ADAPTERS[runtime], source);
}

/** Async probe: acquire through dynamic import, attempt through the shared body. */
async function tryWasmAsync(source: SessionSource): Promise<ResolvedBackend | null> {
  const loaded = await loadAdapterModule(WASM_MODULE);
  if (!loaded || typeof loaded["getWasmPort"] !== "function") return null;
  return resolveWasmFile(loaded as unknown as WasmAdapter, source);
}

async function instantiateFromBytes(
  bytes: Uint8Array,
): Promise<ResolvedBackend> {
  // Prefer the adapter's async gate (off-thread compile, shared module
  // cache); older adapters expose only the synchronous compile.
  const instantiateVia = async (loaded: Record<string, unknown>): Promise<FfiPort | null> => {
    const wasm = loaded as unknown as WasmAdapter;
    if (typeof wasm.portFromBytes === "function") {
      return wasm.portFromBytes(bytes);
    }
    if (typeof wasm.instantiateWasm === "function") {
      return wasm.instantiateWasm(bytes);
    }
    return null;
  };
  const syncLoaded = requireAdapterModule(WASM_MODULE);
  if (syncLoaded) {
    const port = await instantiateVia(syncLoaded);
    if (port) {
      return { port, backend: "wasm", procedures: null, unscannedProcedures: null };
    }
  }
  const loaded = await loadAdapterModule(WASM_MODULE);
  if (loaded) {
    const port = await instantiateVia(loaded);
    if (port) {
      return { port, backend: "wasm", procedures: null, unscannedProcedures: null };
    }
  }
  throw compileGuidance(undefined);
}

/**
 * Asynchronous resolution: fetched `url` sources, byte-fed sources
 * without a synchronous leg, and file or directory sources on runtimes
 * without synchronous `require`. Throws when no leg can serve the source.
 */
export async function resolveAsync(
  source: SessionSource,
  runtime: Runtime,
): Promise<ResolvedBackend> {
  checkSource(source);
  if (source.bytes) {
    return instantiateFromBytes(source.bytes);
  }
  if (source.url !== undefined) {
    const bytes = await fetchModuleBytes(source.url, "galley");
    return instantiateFromBytes(bytes);
  }
  const fromFile = source.filePath !== undefined;
  const display = (fromFile ? source.filePath : source.languagePath) as string;
  if (runtime === "browser") {
    throw new Error(
      fromFile
        ? "galley: browsers cannot read artifact files; pass url or bytes instead"
        : "galley: browsers cannot read language directories; pass url or bytes instead",
    );
  }
  if (runtime !== "node" && runtime !== "bun" && runtime !== "deno") {
    throw compileGuidance(display);
  }
  for (const leg of probeOrder(runtime, source.backend)) {
    const resolved =
      leg === "native"
        ? await tryNativeAsync(runtime, source)
        : await tryWasmAsync(source);
    if (resolved) return resolved;
  }
  throw compileGuidance(display);
}

/** Test-only: clear the fallback, skipped-scan, and legs-consumed notices. */
export function __resetLoader(): void {
  warnedWasm = false;
  legsUsed = false;
  __resetSkippedScan();
}
