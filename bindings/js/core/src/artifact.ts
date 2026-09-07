import { MissingArtifactError } from "./errors.js";

/**
 * Host capabilities artifact resolution needs from each adapter.
 * Node, Bun, and wasm pass `process.env`, `path.resolve`, and an
 * `fs.accessSync` probe; Deno passes `Deno.env.get`, the identity
 * resolver (Deno reports the path it was given), and a `Deno.statSync`
 * probe. Core stays runtime-neutral: no `node:`, `bun:`, or Deno imports.
 */
export interface ArtifactHost {
  getEnv(name: string): string | undefined;
  resolvePath(candidate: string): string;
  existsSync(candidate: string): boolean;
  buildHint: string;
}

/**
 * Shared parser-artifact resolution for every JavaScript adapter.
 * One place is named up front — an explicit path or GALLEY_LIBRARY_PATH.
 * Anything else is a loud error, never a search. Each adapter keeps a
 * thin `findLibrary` wrapper passing its host capabilities and its own
 * build hint; the decision lives here.
 */
export function resolveArtifact(explicit: string | undefined, host: ArtifactHost): string {
  const chosen = explicit || host.getEnv("GALLEY_LIBRARY_PATH");
  if (!chosen) {
    throw new MissingArtifactError(
      "no parser artifact given; pass libraryPath or set GALLEY_LIBRARY_PATH",
      host.buildHint,
    );
  }
  const resolved = host.resolvePath(chosen);
  if (!host.existsSync(resolved)) {
    throw new MissingArtifactError(`at ${resolved}`, host.buildHint);
  }
  return resolved;
}
