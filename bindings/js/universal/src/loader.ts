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
 * There is no `init()`: the universal factories resolve their
 * backend before returning — `openLanguageDirectory` (a directory
 * holding the standard-named artifact; the entry passes its bundled
 * hooks), `galley.load` (an explicit artifact file, no hooks),
 * `galley.loadBytes` (raw wasm), or `galley.loadUrl` (fetched).
 * A factory either returns a usable parser or throws: there is no
 * unready state. All of them are synchronous except `loadUrl`,
 * whose only async step is the fetch.
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
import { MissingArtifactError } from "@sanbus/galley-core";

export type Runtime = "node" | "bun" | "deno" | "browser";
export type Backend = "native" | "wasm";
export type NativeRuntime = "node" | "bun" | "deno";

/** One resolved source naming the parser artifact, plus probe options. Factories pass exactly one source. */
export interface SessionSource {
  /** Language directory holding the standard-named artifact file. */
  languagePath?: string;
  /** Explicit artifact file. Wires nothing; install explicitly on the parser. */
  filePath?: string;
  /** Raw wasm module bytes. */
  bytes?: Uint8Array;
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
}

const NATIVE_ADAPTERS: Record<
  NativeRuntime,
  { module: string; getPort: string; getPortFromFile: string }
> = {
  node: { module: "@sanbus/galley-node", getPort: "getNodePort", getPortFromFile: "getNodePortFromFile" },
  bun: { module: "@sanbus/galley-bun", getPort: "getBunPort", getPortFromFile: "getBunPortFromFile" },
  deno: { module: "@sanbus/galley-deno", getPort: "getDenoPort", getPortFromFile: "getDenoPortFromFile" },
};
const WASM_MODULE = "@sanbus/galley-wasm";

/**
 * Adapter acquisition, injected by the entry point. The loader names
 * backend specifiers but never imports them: an import here would pull
 * the native adapters into every graph that loads this module
 * (bundlers follow bare specifiers because they are installed
 * dependencies), which is exactly what the browser entry must avoid.
 * The default entry (`index.ts`) seeds the Node implementations; the
 * browser entry seeds nothing and never imports this module.
 * Without seeded legs the loader resolves nothing and construction
 * fails with the compile guidance — there is no unseeded fallback import.
 */
export interface EngineLegs {
  /** Synchronous `require`, or absent where none exists (browsers). */
  requireModule?: (specifier: string) => Record<string, unknown>;
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

/** What a backend leg answers: the port and which engine served it. */
interface ProbeResult {
  port: FfiPort;
  backend: Backend;
}

/**
 * A resolved backend: the leg's answer plus the policy fact only the
 * resolution boundary knows — whether wasm was a fallback. True only
 * when wasm served a source that never named wasm: a language
 * directory after the native leg missed. Byte- and `.wasm`-file
 * sources name wasm themselves, and native is the preferred leg, so
 * neither falls back.
 */
export interface ResolvedBackend extends ProbeResult {
  fallback: boolean;
}

let warnedWasm = false;

/**
 * The both-legs-miss failure: an aggregate `MissingArtifactError`, so the
 * machine-readable code is identical here and at the adapters that threw
 * the per-leg misses it swallows. Carries the path and the exact build
 * command the contract requires.
 */
function compileGuidance(directory: string | undefined): MissingArtifactError {
  const target = directory ?? "<language-dir>";
  return new MissingArtifactError(
    `at ${target} (tried native library, then WebAssembly)`,
    `Build one first: npx galley build ${target}`,
  );
}

export function noteWasmFallback(): void {
  if (warnedWasm) return;
  warnedWasm = true;
  console.warn(
    "galley: using the WebAssembly backend (no native library found); " +
      "throughput trails native codegen (roughly three quarters). " +
      "Build a native library for full speed.",
  );
}

/** The single source check: exactly one of the three artifact sources.
 * Empty strings count as absent; factories report the precise error for
 * bad values, so this only guards the seam. Factories pass one source
 * by construction. */
export function checkSource(source: SessionSource): void {
  const present = (value: unknown): boolean => value !== undefined && value !== "";
  const count = [source.languagePath, source.filePath, source.bytes].filter(present).length;
  if (count !== 1) {
    throw new TypeError("galley: Session needs exactly one of languagePath, filePath, bytes");
  }
}

/**
 * Whether the source itself names the wasm engine: raw module bytes
 * (only wasm consumes them) or a file bearing the `.wasm` extension.
 * A language directory names no engine, so wasm serving one is a
 * fallback — the case the one-time notice exists for.
 */
function sourceNamesWasm(source: SessionSource): boolean {
  if (source.bytes !== undefined) return true;
  if (source.filePath === undefined) return false;
  return source.filePath.toLowerCase().endsWith(".wasm");
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
 * The single native-leg attempt: resolves the port for a directory or
 * file source. Missing artifacts yield null (try the next engine).
 * `.wasm` sources never reach dlopen — they yield so the owning engine
 * loads them — and a present-but-broken native library throws loudly.
 * `names` is the runtime's row of the adapter table, so backend export
 * names live in exactly one place.
 */
function useNativeModule(
  loaded: Record<string, unknown>,
  names: { getPort: string; getPortFromFile: string },
  source: SessionSource,
): ProbeResult | null {
  if (sourceNamesWasm(source)) return null;
  const fromFile = source.filePath !== undefined;
  const getPortFn = loaded[fromFile ? names.getPortFromFile : names.getPort];
  if (typeof getPortFn !== "function") return null;
  const artifact = (fromFile ? source.filePath : source.languagePath) as string;
  try {
    const port = (getPortFn as (artifact: string) => FfiPort)(artifact);
    return { port, backend: "native" };
  } catch (error) {
    if (MissingArtifactError.is(error)) return null;
    throw error;
  }
}

/** Sync probe: acquire through require, attempt through the shared body. */
function tryNativeSync(runtime: NativeRuntime, source: SessionSource): ProbeResult | null {
  const loaded = requireAdapterModule(NATIVE_ADAPTERS[runtime].module);
  if (!loaded) return null;
  return useNativeModule(loaded, NATIVE_ADAPTERS[runtime], source);
}

/**
 * The single file-backed wasm attempt. Byte-fed sources bypass it
 * (handled directly in `resolveSync`). Missing artifacts yield null,
 * anything else throws loudly.
 */
function resolveWasmFile(wasm: WasmAdapter, source: SessionSource): ProbeResult | null {
  try {
    if (source.filePath !== undefined) {
      // The wasm leg serves wasm modules: anything else is another
      // engine's artifact, not a miss to compile. Yield so probing (and
      // its loud guidance) keeps working; getWasmPort itself throws for
      // direct callers.
      if (!sourceNamesWasm(source)) return null;
      return {
        port: wasm.getWasmPort({ filePath: source.filePath }),
        backend: "wasm",
      };
    }
    if (source.languagePath === undefined) return null;
    return {
      port: wasm.getWasmPort({ languagePath: source.languagePath }),
      backend: "wasm",
    };
  } catch (error) {
    if (MissingArtifactError.is(error)) return null;
    throw error;
  }
}

/** Sync probe: acquire through require; bytes instantiate directly. */
function tryWasmSync(source: SessionSource): ProbeResult | null {
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
    return { port: wasm.instantiateWasm(source.bytes), backend: "wasm" };
  }
  return resolveWasmFile(wasm, source);
}

/**
 * Stamp the policy fact the probes cannot know: whether the serving
 * engine was chosen as a fallback (probes only report port and engine).
 * `sourceNamesWasm` is the single source of that stamp: only bytes and
 * `.wasm` paths name their engine, so only they pair a wasm port with
 * `fallback: false` — the partition the resolveSync test pins.
 */
function withFallback(source: SessionSource, probe: ProbeResult): ResolvedBackend {
  return { ...probe, fallback: probe.backend === "wasm" && !sourceNamesWasm(source) };
}

/**
 * The one resolution path: native leg first, WebAssembly fallback, and
 * a throw when no leg serves the source. Byte-fed modules instantiate
 * through the wasm leg wherever the adapter loads; invalid bytes
 * propagate (user errors, not fallback cases).
 */
export function resolveSync(source: SessionSource, runtime: Runtime): ResolvedBackend {
  checkSource(source);
  if (source.bytes !== undefined) {
    const resolved = tryWasmSync(source);
    if (resolved) return withFallback(source, resolved);
    throw compileGuidance(undefined);
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
  const resolved = tryNativeSync(runtime, source) ?? tryWasmSync(source);
  if (resolved) return withFallback(source, resolved);
  throw compileGuidance(display);
}

/** Test-only: clear the fallback and legs-consumed notices. */
export function __resetLoader(): void {
  warnedWasm = false;
  legsUsed = false;
}
