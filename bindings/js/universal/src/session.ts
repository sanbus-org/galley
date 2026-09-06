/**
 * Universal `Session`: the core session bound to the resolved backend.
 *
 * Under Node and Bun the backend resolves synchronously on first use;
 * elsewhere `await init()` must complete first.
 */

import { Session as CoreSession } from "galley-js-core";
import type { SessionOptions } from "galley-js-core";
import { ensureSync, type InitOptions } from "./loader.js";

export type UniversalSessionOptions = SessionOptions & InitOptions;
export type { SessionOptions };

export class Session extends CoreSession {
  constructor(options: UniversalSessionOptions = {}) {
    super(ensureSync(options), options);
  }
}
