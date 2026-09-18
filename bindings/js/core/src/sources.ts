/**
 * Session-source checks shared by every JavaScript entry.
 *
 * Factories take exactly one source — a language directory, an explicit
 * artifact file, raw module bytes, or a module URL — and each entry only
 * offers the factories it can serve. These helpers keep that validation
 * in one place so the five session implementations cannot drift. `what`
 * names the calling factory (e.g. `"galley: Session.fromDirectory"`)
 * for error messages.
 */

export function checkLanguagePath(languagePath: unknown, what: string): string {
  if (typeof languagePath !== "string" || languagePath.length === 0) {
    throw new TypeError(`${what} requires languagePath naming the language directory`);
  }
  return languagePath;
}

/** An explicit artifact file path, resolved and existence-checked by the adapter. */
export function checkArtifactPath(filePath: unknown, what: string): string {
  if (typeof filePath !== "string" || filePath.length === 0) {
    throw new TypeError(`${what} requires filePath naming the artifact file`);
  }
  return filePath;
}

/**
 * Raw module bytes. `ArrayBuffer.isView`, not `instanceof`: bytes cross
 * realm boundaries (workers, vm sandboxes) where the constructor
 * differs. Non-`Uint8Array` views normalize through the underlying
 * buffer so every caller instantiates the same bytes.
 */
export function checkModuleBytes(bytes: unknown, what: string): Uint8Array {
  if (!ArrayBuffer.isView(bytes)) {
    throw new TypeError(`${what} requires module bytes`);
  }
  if (bytes instanceof Uint8Array) return bytes;
  const view = bytes as unknown as { buffer: ArrayBufferLike; byteOffset: number; byteLength: number };
  return new Uint8Array(view.buffer, view.byteOffset, view.byteLength);
}

/**
 * A fetchable module URL. Duck-typed (`href`), not `instanceof URL`,
 * for the same cross-realm reason as {@link checkModuleBytes}: `fetch`
 * accepts anything with an `href`.
 */
export function checkModuleUrl(url: unknown, what: string): string | URL {
  if (typeof url === "string") return url;
  if (typeof url === "object" && url !== null && typeof (url as { href?: unknown }).href === "string") {
    return url as URL;
  }
  throw new TypeError(`${what} requires a module URL`);
}

export async function fetchModuleBytes(url: string | URL, what: string): Promise<Uint8Array> {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${what}: failed to fetch ${url}: ${response.status}`);
  return new Uint8Array(await response.arrayBuffer());
}

/**
 * Warning when a procedures file was detected but the runtime cannot
 * auto-load it (Deno has no synchronous module loader): names the file
 * and points at the explicit `procedures` option. One shared copy so
 * the Deno adapter and the universal loader cannot drift.
 */
export function skippedScanMessage(found: string): string {
  return (
    `galley: ${found} was detected but not auto-loaded; ` +
    `pass its hooks through the procedures option.`
  );
}

let warnedSkippedScan = false;

/**
 * Warns once per process when a procedures file was detected but not
 * loaded and no explicit `procedures` were given. The single gate for
 * the Deno adapter and the universal loader, so one process using both
 * entries warns once, not twice. Silent when nothing was found or when
 * the caller already passed hooks explicitly.
 */
export function noteSkippedScan(found: string | null, explicit: unknown): void {
  if (found === null || warnedSkippedScan) return;
  if (explicit !== undefined && explicit !== null) return;
  warnedSkippedScan = true;
  console.warn(skippedScanMessage(found));
}

/** Test-only: clear the skipped-scan notice. */
export function __resetSkippedScan(): void {
  warnedSkippedScan = false;
}
