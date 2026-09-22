/**
 * Session-source checks shared by every JavaScript entry.
 *
 * Factories take exactly one source — a language directory, an explicit
 * artifact file, raw module bytes, or a module URL — and each entry only
 * offers the factories it can serve. These helpers keep that validation
 * in one place so entries cannot drift. `what` names the calling
 * factory (e.g. `"galley: galley.load"`) for error messages.
 */

import { encodeUtf8 } from "./text.ts";

export function checkLanguagePath(languagePath: unknown, what: string): string {
  return checkPath(languagePath, what, "languagePath naming the language directory");
}

/** An explicit artifact file path, resolved and existence-checked by the adapter. */
export function checkArtifactPath(filePath: unknown, what: string): string {
  return checkPath(filePath, what, "filePath naming the artifact file");
}

/**
 * A filesystem path in host-idiomatic form: a string or a `file:` URL.
 * Byte views are not paths — bytes are parse input, not filenames —
 * so anything else is a loud error naming the expected shape.
 * Deliberately dependency-free: no `node:` imports, so browser graphs
 * stay clean.
 */
function checkPath(value: unknown, what: string, expectation: string): string {
  if (typeof value === "string") {
    if (value.length === 0) throw new TypeError(`${what} requires ${expectation}`);
    return rejectInteriorNul(value, what, expectation);
  }
  if (typeof value === "object" && value !== null && typeof (value as { href?: unknown }).href === "string") {
    return rejectInteriorNul(
      fileUrlToPath(value as { href: string }, what, expectation),
      what,
      expectation,
    );
  }
  throw new TypeError(`${what} requires ${expectation}`);
}

/**
 * Filesystem paths cross into native code as NUL-terminated strings,
 * so an interior NUL would silently truncate: reject loudly instead.
 * The single gate for every path entry (language directories, artifact
 * files, parse inputs by path), string and `file:` URL forms alike.
 */
function rejectInteriorNul(path: string, what: string, expectation: string): string {
  if (path.includes("\0")) {
    throw new TypeError(`${what} requires ${expectation} without interior NUL bytes`);
  }
  return path;
}

/** Decodes a `file:` URL to a filesystem path without `node:` imports. */
function fileUrlToPath(url: { href: string }, what: string, expectation: string): string {
  const match = /^file:\/\/([^/]*)([\s\S]*)$/.exec(url.href);
  if (match === null || (match[1] !== "" && match[1] !== "localhost")) {
    throw new TypeError(`${what} requires ${expectation}`);
  }
  let path = decodeURIComponent(match[2]);
  if (/^\/[A-Za-z]:\//.test(path)) path = path.slice(1);
  if (path.length === 0) throw new TypeError(`${what} requires ${expectation}`);
  return path;
}

/**
 * Parse input in host-idiomatic form: a string (encoded once), any
 * `Uint8Array`, any other buffer view (normalized through the
 * underlying buffer), or a bare `ArrayBuffer` / `SharedArrayBuffer`.
 * Anything else is a loud error. `instanceof` fast paths stay ahead of
 * the cross-realm `isView` normalization, exactly like
 * {@link checkModuleBytes}.
 */
export function checkParseInput(input: unknown, what: string): Uint8Array {
  if (typeof input === "string") return encodeUtf8(input);
  if (input instanceof Uint8Array) return input;
  if (typeof ArrayBuffer !== "undefined" && ArrayBuffer.isView(input)) {
    const view = input as unknown as { buffer: ArrayBufferLike; byteOffset: number; byteLength: number };
    return new Uint8Array(view.buffer, view.byteOffset, view.byteLength);
  }
  if (
    (typeof ArrayBuffer !== "undefined" && input instanceof ArrayBuffer) ||
    (typeof SharedArrayBuffer !== "undefined" && input instanceof SharedArrayBuffer)
  ) {
    return new Uint8Array(input as ArrayBuffer);
  }
  throw new TypeError(`${what} requires a string or binary input`);
}

/**
 * Message text in host-idiomatic form: a string (encoded once) or raw
 * bytes. Branching here instead of encoding unconditionally closes the
 * silent-corruption hole where an encoder would stringify a byte array
 * into digit text.
 */
export function checkMessageBytes(value: unknown, what: string): Uint8Array {
  if (typeof value === "string") return encodeUtf8(value);
  return checkModuleBytes(value, what);
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
