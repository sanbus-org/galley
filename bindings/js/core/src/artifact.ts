import { MissingArtifactError } from "./errors.ts";

/**
 * Host capabilities artifact resolution needs from each adapter.
 * Node, Bun, and wasm pass `path.resolve` and an `fs.accessSync` probe;
 * Deno passes the identity resolver (Deno reports the path it was given)
 * and a `Deno.statSync` probe. Core stays runtime-neutral: no `node:`,
 * `bun:`, or Deno imports.
 */
export interface ArtifactHost {
  resolvePath(candidate: string): string;
  existsSync(candidate: string): boolean;
  buildHint: string;
}

/**
 * Shared library filename mapping for every JavaScript adapter.
 * One library name per platform: `lib<base>.dylib` on macOS, `<base>.dll`
 * on Windows (no `lib` prefix), `lib<base>.so` elsewhere. The platform
 * string comes from the host (`process.platform` under Node/Bun, where
 * Windows reports `win32`; `Deno.build.os`, where it reports `windows`);
 * both spellings map to the Windows name here so the adapters cannot
 * diverge. Each adapter keeps a thin `libFileName` wrapper passing its
 * own base name; the mapping lives here.
 */
export function artifactFileName(base: string, platform: string): string {
  if (platform === "darwin") return `lib${base}.dylib`;
  if (platform === "win32" || platform === "windows") return `${base}.dll`;
  return `lib${base}.so`;
}

/**
 * Base name of the one shared native library `galley build` leaves next to
 * the grammar (`artifactFileName` maps it per platform). It serves the
 * Node, Bun, and Deno adapters alike; the per-adapter single-leg builders
 * emit their own names for adapter-only flows. This literal must match
 * `NATIVE_LIBRARY_BASE` in `core/build/builder.mjs` (separate module
 * systems: plain node `.mjs` versus compiled TS, so one cannot import the
 * other — the universal loader suite pins them equal).
 */
export const SHARED_NATIVE_LIBRARY_BASE = "galley-js-node";

/**
 * Shared wasm artifact filename. WebAssembly modules are platform-neutral:
 * always `lib<base>.wasm`. The wasm adapter keeps a thin `wasmFileName`
 * wrapper passing its base name.
 */
export function wasmArtifactFileName(base: string): string {
  return `lib${base}.wasm`;
}

/**
 * Canonical path for cache identity, shared by every adapter: symlinked
 * spellings of one file must resolve to one key, or same-file sessions
 * get separate ports with separate gate stacks over one native gate set.
 * Each adapter injects its spelling steps — lexical resolution plus the
 * realpath call (Deno keeps its identity lexical step, so missing-file
 * messages still name the path as passed). Falls back to the lexical
 * spelling only when the file is absent (`ENOENT`/`ENOTDIR`, which Deno
 * also reports as `code`); any other I/O failure rethrows rather than
 * forking the cache.
 */
export function canonicalResolvePath(
  candidate: string,
  resolveLexical: (candidate: string) => string,
  realPath: (lexical: string) => string,
): string {
  const lexical = resolveLexical(candidate);
  try {
    return realPath(lexical);
  } catch (error) {
    const code = (error as { code?: unknown } | null)?.code;
    if (code === "ENOENT" || code === "ENOTDIR") return lexical;
    throw error;
  }
}

/**
 * Shared parser-artifact resolution for every JavaScript adapter.
 * Exactly one place is named: `directory` must hold the adapter's
 * standard-named file (`fileName`). Anything else is a loud error, never
 * a search. Each adapter keeps a thin wrapper passing its own standard
 * file name; the decision lives here.
 */
export function resolveArtifact(
  directory: string | undefined,
  fileName: string,
  joinPath: (...parts: string[]) => string,
  host: ArtifactHost,
): string {
  if (!directory) {
    throw new MissingArtifactError(
      "no language directory given; pass languagePath",
      host.buildHint,
    );
  }
  const resolved = host.resolvePath(joinPath(directory, fileName));
  if (!host.existsSync(resolved)) {
    throw new MissingArtifactError(`at ${resolved}`, host.buildHint);
  }
  return resolved;
}

/**
 * Adapter directory resolution with the shared-library fallback. Bun and
 * Deno try their adapter-specific standard file first (single-leg builder
 * flows keep resolving exactly what they built), then the shared native
 * library `galley build` leaves (which serves every native adapter). Both
 * candidates are exact standard names — no directory walk, no glob. When
 * neither exists the error names both tried paths, so the message still
 * tells the user everything `galley build` would have provided.
 */
export function resolveAdapterArtifact(
  directory: string | undefined,
  adapterFileName: string,
  sharedFileName: string,
  joinPath: (...parts: string[]) => string,
  host: ArtifactHost,
): string {
  if (directory === undefined) {
    return resolveArtifact(directory, adapterFileName, joinPath, host);
  }
  try {
    return resolveArtifact(directory, adapterFileName, joinPath, host);
  } catch (error) {
    if (!MissingArtifactError.is(error)) throw error;
    try {
      return resolveArtifact(directory, sharedFileName, joinPath, host);
    } catch (fallbackError) {
      if (!MissingArtifactError.is(fallbackError)) throw fallbackError;
      throw new MissingArtifactError(
        `at ${host.resolvePath(joinPath(directory, adapterFileName))}, then at ${host.resolvePath(joinPath(directory, sharedFileName))}`,
        host.buildHint,
      );
    }
  }
}

/**
 * Explicit-file twin of {@link resolveArtifact}: `filePath` names the
 * artifact itself instead of a directory holding the standard name.
 * Anything else is a loud error naming the resolved path, never a
 * search. The universal `galley.load` uses this behind the scenes.
 */
export function resolveArtifactFile(filePath: string | undefined, host: ArtifactHost): string {
  if (!filePath) {
    throw new MissingArtifactError("no artifact file given; pass filePath", host.buildHint);
  }
  const resolved = host.resolvePath(filePath);
  if (!host.existsSync(resolved)) {
    throw new MissingArtifactError(`at ${resolved}`, host.buildHint);
  }
  return resolved;
}
