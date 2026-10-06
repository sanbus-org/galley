/**
 * Node-only file and module access for the WebAssembly adapter.
 *
 * Imported exclusively by the Node entry (`index.ts`), never by the
 * browser entry (`browser.ts`): every `node:` specifier in this package
 * lives in this one module, so a bundler resolving the `browser` export
 * condition never sees them. `ffi.ts` reaches this module only through
 * the seed wired in `index.ts`.
 */

import * as fs from "node:fs";
import * as path from "node:path";

import { canonicalResolvePath } from "@sanbus/galley-core/internal";
import type { FileIo } from "./ffi.ts";

/** `FileIo` over the real filesystem. */
export const nodeFileIo: FileIo = {
  existsSync(localPath: string): boolean {
    // fs.existsSync (not accessSync): under Deno, accessSync demands
    // --allow-sys ("uid") while existsSync needs only --allow-read,
    // and this entry also serves Deno through the universal loader.
    return fs.existsSync(localPath);
  },
  readFile(localPath: string): Uint8Array {
    return new Uint8Array(fs.readFileSync(localPath));
  },
  resolvePath(candidate: string): string {
    // Shared canonicalization (see core artifact.ts): symlinked
    // spellings share one cached port; absent files keep the lexical
    // spelling so missing artifacts still report MissingArtifactError.
    return canonicalResolvePath(candidate, path.resolve, fs.realpathSync);
  },
};
