/**
 * Internal cross-package surface for first-party consumers (adapters,
 * the universal loader, builders, and suites).
 *
 * Anything imported here may change without a major version bump; user
 * code must depend only on the package root. Types stay on the root
 * (they erase at compile time); only runtime helpers live here.
 */

export {
  resolveArtifact,
  resolveArtifactFile,
  resolveAdapterArtifact,
  artifactFileName,
  wasmArtifactFileName,
  canonicalResolvePath,
  SHARED_NATIVE_LIBRARY_BASE,
} from "./artifact.ts";
export { displayTokenName } from "./diagnostic.ts";
export { isProcedureName, loadProceduresModule, registryFor, __resetSharedRegistries } from "./procedures.ts";
export {
  checkLanguagePath,
  checkArtifactPath,
  checkModuleBytes,
  checkModuleUrl,
  checkParseInput,
  checkMessageBytes,
  fetchModuleBytes,
  skippedScanMessage,
  noteSkippedScan,
  __resetSkippedScan,
} from "./sources.ts";
export { encodeUtf8, decodeUtf8, byteLengthUtf8 } from "./text.ts";

/**
 * Rejects option keys outside the allowed set: option bags are checked
 * at runtime because untyped callers bypass the interfaces. Each
 * factory passes its own allowlist.
 */
export function rejectSessionOptions(
  options: Record<string, unknown>,
  what: string,
  allowed: ReadonlySet<string>,
): void {
  const unexpected = Object.keys(options).filter((key) => !allowed.has(key));
  if (unexpected.length > 0) {
    throw new TypeError(
      `galley: ${what} does not accept ${unexpected.join(", ")}; parser tunables belong to openSession`,
    );
  }
}

/**
 * Content hash for byte-fed handles: the same bytes must resolve to the
 * identical handle, and bytes carry no path to key on. cyrb53 over
 * content plus length: fast number ops, no dependencies (`node:crypto`
 * would poison browser import graphs).
 */
export function hashModuleBytes(bytes: Uint8Array): string {
  let h1 = 0xdeadbeef;
  let h2 = 0x41c6ce57;
  for (const byte of bytes) {
    h1 = Math.imul(h1 ^ byte, 2654435761);
    h2 = Math.imul(h2 ^ byte, 1597334677);
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  return `${bytes.length}:${(h2 >>> 0).toString(16)}${(h1 >>> 0).toString(16)}`;
}
